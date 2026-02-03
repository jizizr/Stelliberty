package io.github.stelliberty.android.clash_core

import android.util.Log
import java.io.File
import java.io.FileOutputStream

// 核心配置管理：负责准备和管理 Clash 配置文件
object ClashCoreConfig {
    private const val logTag = "clash_core_config"

    // 配置文件名
    const val configFileName = "config.yaml"

    // 默认最小配置
    private val defaultConfig =
        """
        mixed-port: 7777
        allow-lan: true
        mode: rule
        log-level: info
        proxies: []
        proxy-groups: []
        rules:
          - MATCH,DIRECT
    """
            .trimIndent()

    // 确保配置文件已准备好（优先使用 configPath，其次保留现有或生成默认）
    fun ensureConfigPrepared(
        homeDir: File,
        configPath: String?,
        shouldPreserveExisting: Boolean = false,
    ) {
        val outFile = File(homeDir, configFileName)

        // 优先使用指定的配置文件
        if (!configPath.isNullOrBlank()) {
            val src = File(configPath)
            if (src.exists() && src.isFile) {
                Log.i(logTag, "使用配置文件: ${src.absolutePath}")
                src.inputStream().use { input ->
                    FileOutputStream(outFile).use { output -> input.copyTo(output) }
                }
                Log.i(logTag, "配置就绪: path=${outFile.absolutePath} size=${outFile.length()}")
                return
            }
        }

        // 保留现有配置（如果允许且存在）
        if (shouldPreserveExisting && outFile.exists() && outFile.length() > 0) {
            Log.i(logTag, "保留现有配置: ${outFile.absolutePath}")
            return
        }

        // 使用默认配置
        Log.w(logTag, "配置路径无效，使用默认配置")
        outFile.writeText(defaultConfig)
        Log.i(logTag, "默认配置就绪: path=${outFile.absolutePath} size=${outFile.length()}")
    }
}
