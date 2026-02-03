package io.github.stelliberty.android.clash_core

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.github.stelliberty.MainActivity
import java.io.File
import org.json.JSONObject

// 核心运行时管理：负责在宿主进程内初始化核心 so 并提供状态缓存
// 该层只负责核心生命周期与资源准备，不承载业务逻辑
object ClashCoreRuntime {
    private const val logTag = "clash_core_runtime"

    private val stateLock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var isInitialized: Boolean = false

    @Volatile private var coreVersion: String? = null

    @Volatile private var startedAtMs: Long? = null

    // 已打印过的事件类型集合，避免重复打印
    private val loggedEventTypes = mutableSetOf<String>()

    // 核心事件监听器：转发日志到 Flutter 端
    private val coreEventListener = ClashCoreResultCallback { result ->
        if (result.isNullOrBlank()) {
            return@ClashCoreResultCallback
        }

        // 解析并简化日志输出
        try {
            val json = JSONObject(result)
            val method = json.optString("method")
            if (method == "message") {
                val data = json.optJSONObject("data")
                val type = data?.optString("type")
                if (type == "log") {
                    val logData = data?.optJSONObject("data")
                    val level = logData?.optString("level") ?: "info"
                    val payload = logData?.optString("payload") ?: ""
                    Log.d(logTag, "[$level] $payload")
                } else if (type != null) {
                    // 只在首次收到该类型事件时打印
                    if (loggedEventTypes.add(type)) {
                        Log.d(logTag, "事件流已建立: $type")
                    }
                }
            }
        } catch (e: Exception) {
            Log.d(logTag, "核心事件: $result")
        }

        // 转发日志到 Flutter 端
        mainHandler.post { MainActivity.coreLogEventSink?.success(result) }
    }

    fun isCoreInitialized(): Boolean = isInitialized

    fun getCoreVersion(): String? = coreVersion

    fun getStartedAtMs(): Long? = startedAtMs

    // 确保核心已初始化（幂等）
    fun ensureInitialized(context: Context, configPath: String?): Boolean {
        synchronized(stateLock) {
            return try {
                val homeDir = File(context.filesDir, "clash-core")
                if (!homeDir.exists() && !homeDir.mkdirs()) {
                    Log.e(logTag, "创建主目录失败")
                    false
                } else {
                    initCoreInternal(context, homeDir, configPath)
                }
            } catch (e: Exception) {
                Log.e(logTag, "初始化失败", e)
                false
            }
        }
    }

    // 内部初始化逻辑
    private fun initCoreInternal(context: Context, homeDir: File, configPath: String?): Boolean {
        // 从 APK lib 目录获取核心 so 路径
        val coreSoPath = ClashCoreAssets.getCoreSoPath(context)
        ClashCoreBridge.nativeInit(coreSoPath)

        // 设置事件监听器（用于接收日志等事件）
        ClashCoreBridge.nativeSetEventListener(coreEventListener)

        ClashCoreAssets.ensureGeoDataExtracted(context, homeDir)
        ClashCoreConfig.ensureConfigPrepared(
            homeDir = homeDir,
            configPath = configPath,
            shouldPreserveExisting = isInitialized && configPath.isNullOrBlank(),
        )

        val initParams =
            JSONObject().put("home-dir", homeDir.absolutePath).put("version", Build.VERSION.SDK_INT)

        val initResult =
            ClashCoreBridgeHelper.invokeActionSync(method = "initClash", data = initParams)
        val initOk = initResult.optBoolean("data", false)
        if (!initOk) {
            Log.e(logTag, "初始化 Clash 失败: $initResult")
            return false
        }

        val setupResult =
            ClashCoreBridgeHelper.invokeActionSync(method = "setupConfig", data = "{}")
        val setupErr = setupResult.optString("data", "")
        if (setupErr.isNotEmpty()) {
            Log.e(logTag, "配置加载失败: $setupErr")
            return false
        }

        val versionResult =
            ClashCoreBridgeHelper.invokeActionSync(method = "getVersion", data = JSONObject.NULL)
        val version = versionResult.optString("data", "").trim()
        if (version.isNotEmpty()) {
            coreVersion = version
        } else if (coreVersion.isNullOrBlank()) {
            coreVersion = "Unknown"
        }

        if (startedAtMs == null) {
            startedAtMs = System.currentTimeMillis()
        }

        isInitialized = true
        return true
    }
}
