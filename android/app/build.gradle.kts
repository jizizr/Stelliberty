import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.diffplug.spotless") version "7.0.2"
}

// 查找 rustls-platform-verifier 的 Maven 仓库路径
fun findRustlsPlatformVerifierProject(): String {
    val dependencyText = providers.exec {
        workingDir = file("../../native/hub")
        commandLine("cargo", "metadata", "--format-version", "1", "--filter-platform", "aarch64-linux-android")
    }.standardOutput.asText.get()

    val dependencyJson = JsonSlurper().parseText(dependencyText) as Map<*, *>
    val packages = dependencyJson["packages"] as List<*>
    val pkg = packages.find { (it as Map<*, *>)["name"] == "rustls-platform-verifier-android" } as Map<*, *>
    val manifestPath = file(pkg["manifest_path"] as String)
    return File(manifestPath.parentFile, "maven").path
}

// 目标架构（由构建脚本通过 gradle.properties 传入）
val targetAbi = project.findProperty("targetAbi")?.toString()

android {
    namespace = "io.github.stelliberty"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (System.getenv("ANDROID_KEYSTORE_PATH") != null) {
            create("release") {
                storeFile = file(System.getenv("ANDROID_KEYSTORE_PATH")!!)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    defaultConfig {
        applicationId = "io.github.stelliberty"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // CMake 编译 JNI 桥接库
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    // 添加预编译的核心 so 文件路径
    sourceSets {
        getByName("main") {
            java.setSrcDirs(listOf("src/main/kotlin", "src/main/java"))
            jniLibs.srcDirs("../../assets/jniLibs")
        }
    }

    // 根据 targetAbi 排除不需要的架构 SO 文件
    if (targetAbi != null) {
        packagingOptions {
            jniLibs {
                val allAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")
                excludes += allAbis.filter { it != targetAbi }.map { abi -> "lib/$abi/*" }
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

spotless {
    kotlin {
        target("src/**/*.kt")
        ktfmt().kotlinlangStyle()
    }
}

repositories {
    maven {
        url = uri(findRustlsPlatformVerifierProject())
        metadataSources.artifact()
    }
}

dependencies {
    implementation("rustls:rustls-platform-verifier:latest.release")
}
