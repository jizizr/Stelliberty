package io.github.stelliberty.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.github.stelliberty.MainActivity
import io.github.stelliberty.R
import io.github.stelliberty.android.clash_core.ClashCoreAssets
import io.github.stelliberty.android.clash_core.ClashCoreBridge
import io.github.stelliberty.android.clash_core.ClashCoreBridgeHelper
import io.github.stelliberty.android.clash_core.ClashCoreConfig
import io.github.stelliberty.android.clash_core.ClashCoreResultCallback
import java.io.File
import java.util.concurrent.Executors
import org.json.JSONObject

// VPN 服务：负责建立系统 TUN 并驱动核心启停
// 该层只负责生命周期与资源编排，不承载业务逻辑
class VpnService : android.net.VpnService() {
    companion object {
        // 启动 VPN 的 Intent Action
        const val actionStart = "io.github.stelliberty.action.START_VPN"
        // 停止 VPN 的 Intent Action
        const val actionStop = "io.github.stelliberty.action.STOP_VPN"
        // 配置文件路径的 Intent Extra Key
        const val extraConfigPath = "configPath"
        // 访问控制模式的 Intent Extra Key
        const val extraAccessControlMode = "accessControlMode"
        // 访问控制应用列表的 Intent Extra Key
        const val extraAccessControlList = "accessControlList"

        // 访问控制模式常量
        const val accessControlModeDisabled = 0
        const val accessControlModeWhitelist = 1
        const val accessControlModeBlacklist = 2

        private const val logTag = "vpn_service"
        private const val notificationChannelId = "stelliberty_vpn"
        private const val notificationId = 1001

        @Volatile private var isRunningFlag: Boolean = false

        // 获取 VPN 运行状态
        fun isRunning(): Boolean = isRunningFlag
    }

    // 工作线程池（单线程，确保操作顺序执行）
    private val worker = Executors.newSingleThreadExecutor()
    private val stateLock = Any()
    private var isStarting: Boolean = false

    // 访问控制配置
    private var accessControlMode: Int = accessControlModeDisabled
    private var accessControlList: List<String> = emptyList()

    // 核心事件监听器（用于接收并打印核心日志）
    private val coreEventListener = ClashCoreResultCallback { result ->
        if (result.isNullOrBlank()) {
            return@ClashCoreResultCallback
        }
        Log.d(logTag, "核心事件: $result")
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(logTag, "服务创建")
        startForeground(notificationId, buildNotification("VPN 准备中"))
    }

    override fun onDestroy() {
        Log.i(logTag, "服务销毁")
        worker.shutdownNow()
        super.onDestroy()
    }

    override fun onRevoke() {
        Log.w(logTag, "VPN 权限被撤销")
        worker.execute { handleStop() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            actionStart -> {
                val configPath = intent.getStringExtra(extraConfigPath)
                accessControlMode = intent.getIntExtra(extraAccessControlMode, accessControlModeDisabled)
                accessControlList = intent.getStringArrayListExtra(extraAccessControlList) ?: emptyList()
                worker.execute { handleStart(configPath) }
            }

            actionStop -> worker.execute { handleStop() }
        }
        return START_STICKY
    }

    // 处理 VPN 启动
    private fun handleStart(configPath: String?) {
        synchronized(stateLock) {
            if (isStarting || isRunningFlag) {
                return
            }
            isStarting = true
        }

        try {
            Log.i(logTag, "开始启动: configPath=${configPath ?: ""}")
            val homeDir = File(filesDir, "clash-core")
            if (!homeDir.exists() && !homeDir.mkdirs()) {
                throw IllegalStateException("创建主目录失败")
            }
            Log.i(logTag, "主目录=${homeDir.absolutePath}")

            // 从 APK 的 lib 目录定位核心 so
            val coreSoPath = ClashCoreAssets.getCoreSoPath(applicationContext)
            Log.i(logTag, "核心路径=$coreSoPath")
            ClashCoreBridge.nativeInit(coreSoPath)

            // 设置事件监听器（用于接收日志）
            ClashCoreBridge.nativeSetEventListener(coreEventListener)

            // 解压地理数据和配置
            ClashCoreAssets.ensureGeoDataExtracted(assets, homeDir)
            ClashCoreConfig.ensureConfigPrepared(homeDir, configPath)

            // 初始化核心
            val initParams =
                JSONObject()
                    .put("home-dir", homeDir.absolutePath)
                    .put("version", Build.VERSION.SDK_INT)

            val initResult =
                ClashCoreBridgeHelper.invokeActionSync(method = "initClash", data = initParams)
            Log.i(logTag, "初始化结果=$initResult")
            val initOk = initResult.optBoolean("data", false)
            if (!initOk) {
                throw IllegalStateException("核心初始化失败")
            }

            // 启动日志订阅
            ClashCoreBridgeHelper.invokeActionSync(method = "startLog", data = JSONObject())

            // 加载配置
            val setupResult =
                ClashCoreBridgeHelper.invokeActionSync(method = "setupConfig", data = "{}")
            Log.i(logTag, "配置结果=$setupResult")
            val setupErr = setupResult.optString("data", "")
            if (setupErr.isNotEmpty()) {
                throw IllegalStateException("配置加载失败: $setupErr")
            }

            // 建立 TUN 并启动
            val (tunFd, stack, address, dns) = establishTun()
            Log.i(logTag, "TUN 建立成功: fd=$tunFd stack=$stack address=$address dns=$dns")
            val started = ClashCoreBridge.nativeStartTun(tunFd, this, stack, address, dns)
            if (!started) {
                throw IllegalStateException("启动 TUN 失败")
            }
            Log.i(logTag, "TUN 启动成功")

            isRunningFlag = true
            updateNotification("VPN 已连接")
        } catch (e: Exception) {
            Log.e(logTag, "VPN 启动失败", e)
            updateNotification("VPN 启动失败")
            handleStop()
        } finally {
            synchronized(stateLock) { isStarting = false }
        }
    }

    // 处理 VPN 停止
    private fun handleStop() {
        synchronized(stateLock) {
            if (!isRunningFlag && !isStarting) {
                stopSelf()
                return
            }
            isRunningFlag = false
            isStarting = false
        }

        Log.i(logTag, "停止 VPN")
        try {
            try {
                ClashCoreBridge.nativeStopTun()
            } catch (_: Exception) {
                // 忽略核心未初始化或已退出的情况
            }
        } finally {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION") stopForeground(true)
            }
            stopSelf()
        }
    }

    // 建立 TUN 设备
    private fun establishTun(): TunParams {
        val address = "172.19.0.1/30"
        val dns = "172.19.0.2"
        val stack = "system"

        val builder =
            Builder()
                .addAddress("172.19.0.1", 30)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("172.19.0.2")
                .setMtu(9000)
                .setSession("stelliberty")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
            builder.setBlocking(false)
        }

        // 应用访问控制
        applyAccessControl(builder)

        val fd = builder.establish()?.detachFd() ?: throw IllegalStateException("系统拒绝建立 VPN")

        return TunParams(tunFd = fd, stack = stack, address = address, dns = dns)
    }

    // 应用访问控制规则
    private fun applyAccessControl(builder: Builder) {
        val myPackageName = packageName

        when (accessControlMode) {
            accessControlModeWhitelist -> {
                // 白名单模式：只有列表中的应用走 VPN
                Log.i(logTag, "应用白名单模式，应用数量: ${accessControlList.size}")
                // 必须包含自身，否则无法控制 VPN
                builder.addAllowedApplication(myPackageName)
                accessControlList.forEach { pkg ->
                    if (pkg != myPackageName) {
                        try {
                            builder.addAllowedApplication(pkg)
                        } catch (e: Exception) {
                            Log.w(logTag, "添加白名单应用失败: $pkg", e)
                        }
                    }
                }
            }

            accessControlModeBlacklist -> {
                // 黑名单模式：列表中的应用不走 VPN
                Log.i(logTag, "应用黑名单模式，应用数量: ${accessControlList.size}")
                accessControlList.forEach { pkg ->
                    // 不能排除自身
                    if (pkg != myPackageName) {
                        try {
                            builder.addDisallowedApplication(pkg)
                        } catch (e: Exception) {
                            Log.w(logTag, "添加黑名单应用失败: $pkg", e)
                        }
                    }
                }
            }

            else -> {
                // 禁用模式：所有应用都走 VPN
                Log.i(logTag, "访问控制已禁用")
            }
        }
    }

    // 更新通知内容
    private fun updateNotification(text: String) {
        val manager =
            ContextCompat.getSystemService(this, NotificationManager::class.java) ?: return
        manager.notify(notificationId, buildNotification(text))
    }

    // 构建前台服务通知
    private fun buildNotification(text: String): Notification {
        val manager =
            ContextCompat.getSystemService(this, NotificationManager::class.java)
                ?: throw IllegalStateException("通知管理器不可用")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel =
                NotificationChannel(
                    notificationChannelId,
                    "VPN",
                    NotificationManager.IMPORTANCE_LOW,
                )
            manager.createNotificationChannel(channel)
        }

        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent =
            PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

        return NotificationCompat.Builder(this, notificationChannelId)
            .setContentTitle("VPN")
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    // TUN 参数数据类
    private data class TunParams(
        val tunFd: Int,
        val stack: String,
        val address: String,
        val dns: String,
    )
}
