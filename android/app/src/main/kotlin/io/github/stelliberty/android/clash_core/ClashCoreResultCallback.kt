package io.github.stelliberty.android.clash_core

// 核心回调：用于接收核心侧异步返回的 JSON 字符串（结果或事件）。
fun interface ClashCoreResultCallback {
    fun onResult(result: String?)
}
