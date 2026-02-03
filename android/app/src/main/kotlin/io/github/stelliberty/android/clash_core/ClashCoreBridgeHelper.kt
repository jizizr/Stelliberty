package io.github.stelliberty.android.clash_core

import java.util.concurrent.TimeUnit
import org.json.JSONObject

// 核心桥接工具：提供与 Clash 核心交互的通用方法
object ClashCoreBridgeHelper {
    // 默认超时时间（毫秒）
    private const val defaultTimeoutMs = 15_000L

    // 同步调用核心方法，超时抛出 IllegalStateException
    fun invokeActionSync(
        method: String,
        data: Any?,
        timeoutMs: Long = defaultTimeoutMs,
    ): JSONObject {
        val lock = Object()
        var rawResult: String? = null

        val cb = ClashCoreResultCallback { result ->
            synchronized(lock) {
                rawResult = result ?: ""
                lock.notifyAll()
            }
        }

        val action =
            JSONObject()
                .put("id", System.nanoTime().toString())
                .put("method", method)
                .put("data", data ?: JSONObject.NULL)

        ClashCoreBridge.nativeInvokeAction(action.toString(), cb)

        synchronized(lock) {
            val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
            while (rawResult == null) {
                val remainingNanos = deadline - System.nanoTime()
                if (remainingNanos <= 0) {
                    break
                }
                val remainingMs = TimeUnit.NANOSECONDS.toMillis(remainingNanos)
                if (remainingMs <= 0) {
                    break
                }
                try {
                    lock.wait(remainingMs)
                } catch (_: InterruptedException) {
                    break
                }
            }
        }

        val raw = rawResult ?: throw IllegalStateException("调用超时: $method")
        return JSONObject(raw)
    }
}
