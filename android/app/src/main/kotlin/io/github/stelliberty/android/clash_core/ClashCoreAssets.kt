package io.github.stelliberty.android.clash_core

import android.content.Context
import android.content.res.AssetManager
import android.util.Log
import java.io.File
import java.io.FileOutputStream

// 核心资源管理：负责定位核心 so 和解压地理数据文件
object ClashCoreAssets {
    private const val logTag = "clash_core_assets"

    // 地理数据文件基础路径（Flutter assets）
    private const val geoDataAssetBasePath = "flutter_assets/assets/clash"

    // 地理数据文件列表
    private val geoDataFiles =
        listOf("asn.mmdb", "country.mmdb", "geoip.dat", "geoip.metadb", "geosite.dat")

    // 获取核心 so 路径（从 APK 的 lib 目录加载）
    fun getCoreSoPath(context: Context): String {
        val nativeLibDir = context.applicationInfo.nativeLibraryDir
        val soPath = File(nativeLibDir, "libclash.so").absolutePath
        Log.i(logTag, "核心 so 路径: $soPath")
        return soPath
    }

    // 确保地理数据文件已解压
    fun ensureGeoDataExtracted(context: Context, homeDir: File) {
        ensureGeoDataExtracted(context.assets, homeDir)
    }

    // 确保地理数据文件已解压（使用 AssetManager）
    fun ensureGeoDataExtracted(assets: AssetManager, homeDir: File) {
        for (name in geoDataFiles) {
            val assetPath = "$geoDataAssetBasePath/$name"
            val outFile = File(homeDir, name)
            copyAssetIfNeeded(assets, assetPath, outFile)
        }
    }

    // 按需复制资源文件（已存在则跳过）
    private fun copyAssetIfNeeded(assets: AssetManager, assetPath: String, outFile: File) {
        if (outFile.exists() && outFile.length() > 0) {
            return
        }
        copyAsset(assets, assetPath, outFile)
    }

    // 复制资源文件到本地（原子操作）
    private fun copyAsset(assets: AssetManager, assetPath: String, outFile: File) {
        outFile.parentFile?.mkdirs()
        val tmpFile = File(outFile.parentFile, "${outFile.name}.tmp")

        assets.open(assetPath).use { input ->
            FileOutputStream(tmpFile).use { output -> input.copyTo(output) }
        }

        if (outFile.exists()) {
            outFile.delete()
        }

        if (!tmpFile.renameTo(outFile)) {
            Log.w(logTag, "重命名临时文件失败: ${tmpFile.absolutePath}")
            assets.open(assetPath).use { input ->
                FileOutputStream(outFile).use { output -> input.copyTo(output) }
            }
            tmpFile.delete()
        }
    }
}
