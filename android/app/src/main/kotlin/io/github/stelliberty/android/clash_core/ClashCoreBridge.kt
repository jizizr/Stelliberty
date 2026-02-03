package io.github.stelliberty.android.clash_core

import android.net.VpnService

// 核心 JNI 桥接入口：仅负责加载桥接库并暴露 native 方法。
// 业务逻辑（配置、VPN 生命周期编排）必须放在上层模块中。
object ClashCoreBridge {
    init {
        System.loadLibrary("clash_core_bridge")
    }

    external fun nativeInit(corePath: String)

    external fun nativeStartTun(
        fd: Int,
        vpnService: VpnService,
        stack: String,
        address: String,
        dns: String,
    ): Boolean

    external fun nativeStopTun()

    external fun nativeInvokeAction(data: String, cb: ClashCoreResultCallback)

    external fun nativeSetEventListener(cb: ClashCoreResultCallback?)

    external fun nativeSuspend(suspended: Boolean)

    external fun nativeForceGc()

    external fun nativeUpdateDns(dns: String)

    external fun nativeGetTraffic(onlyStatisticsProxy: Boolean): String

    external fun nativeGetTotalTraffic(onlyStatisticsProxy: Boolean): String
}
