// 系统配置消息协议
//
// 目的：定义开机自启动、URL 启动、UWP 回环豁免等系统配置的通信接口

use crate::system::auto_start;
use log::{error, info};
use rinf::{DartSignal, RustSignal};
use serde::{Deserialize, Serialize};

// ============================================================================
// 开机自启动消息协议
// ============================================================================

// Dart → Rust：获取开机自启状态
#[derive(Deserialize, DartSignal)]
pub struct GetAutoStartStatus;

// Dart → Rust：设置开机自启状态
#[derive(Deserialize, DartSignal)]
pub struct SetAutoStartStatus {
    pub enabled: bool,
}

// Rust → Dart：开机自启状态响应
#[derive(Serialize, RustSignal)]
pub struct AutoStartStatusResult {
    pub enabled: bool,
    pub error_message: Option<String>,
}

impl GetAutoStartStatus {
    // 查询当前自启动配置状态
    //
    // 目的：读取系统中的开机自启动设置
    pub fn handle(&self) {
        info!("收到获取开机自启动状态请求");

        let (enabled, error_message) = match auto_start::get_auto_start_status() {
            Ok(status) => (status, None),
            Err(err) => {
                error!("获取开机自启状态失败：{}", err);
                (false, Some(err))
            }
        };

        let response = AutoStartStatusResult {
            enabled,
            error_message,
        };

        response.send_signal_to_dart();
    }
}

impl SetAutoStartStatus {
    // 修改自启动配置
    //
    // 目的：启用或禁用应用程序的开机自启动
    pub fn handle(&self) {
        info!("收到设置开机自启动状态请求：enabled={}", self.enabled);

        let (enabled, error_message) = match auto_start::set_auto_start_status(self.enabled) {
            Ok(status) => (status, None),
            Err(err) => {
                error!("设置开机自启状态失败：{}", err);
                (false, Some(err))
            }
        };

        let response = AutoStartStatusResult {
            enabled,
            error_message,
        };

        response.send_signal_to_dart();
    }
}

// ============================================================================
// URL 启动器消息协议
// ============================================================================

// Dart → Rust：打开 URL
#[derive(Deserialize, DartSignal)]
pub struct OpenUrl {
    pub url: String,
}

// Rust → Dart：打开 URL 结果
#[derive(Serialize, RustSignal)]
pub struct OpenUrlResult {
    pub success: bool,
    pub error_message: Option<String>,
}

impl OpenUrl {
    // 在系统默认浏览器中打开 URL
    //
    // 目的：提供跨平台的 URL 打开能力
    pub fn handle(&self) {
        info!("收到打开 URL 请求：{}", self.url);

        let (success, error_message) = match crate::system::url_launcher::open_url(&self.url) {
            Ok(()) => (true, None),
            Err(err) => {
                error!("打开 URL 失败：{}", err);
                (false, Some(err))
            }
        };

        let response = OpenUrlResult {
            success,
            error_message,
        };

        response.send_signal_to_dart();
    }
}

// ============================================================================
// UWP 回环豁免消息协议（仅 Windows）
// ============================================================================

#[cfg(target_os = "windows")]
pub mod loopback_messages {
    use log::{error, info};
    use rinf::{DartSignal, RustSignal};
    use serde::{Deserialize, Serialize};

    // Dart → Rust：获取所有应用容器
    #[derive(Deserialize, DartSignal)]
    pub struct GetAppContainers;

    // Dart → Rust：设置回环豁免
    #[derive(Deserialize, DartSignal)]
    pub struct SetLoopback {
        pub package_family_name: String,
        pub enabled: bool,
    }

    // Dart → Rust：保存配置（使用 SID 字符串）
    #[derive(Deserialize, DartSignal)]
    pub struct SaveLoopbackConfiguration {
        pub sid_strings: Vec<String>,
    }

    // Rust → Dart：应用容器列表（用于初始化）
    #[derive(Serialize, RustSignal)]
    pub struct AppContainersList {
        pub containers: Vec<String>,
    }

    // Rust → Dart：单个应用容器信息
    #[derive(Serialize, RustSignal)]
    pub struct AppContainerInfo {
        pub app_container_name: String,
        pub display_name: String,
        pub package_family_name: String,
        pub sid: Vec<u8>,
        pub sid_string: String,
        pub is_loopback_enabled: bool,
    }

    // Rust → Dart：设置回环豁免结果
    #[derive(Serialize, RustSignal)]
    pub struct SetLoopbackResult {
        pub success: bool,
        pub message: String,
    }

    // Rust → Dart：应用容器流传输完成信号
    #[derive(Serialize, RustSignal)]
    pub struct AppContainersComplete;

    // Rust → Dart：保存配置结果
    #[derive(Serialize, RustSignal)]
    pub struct SaveLoopbackConfigurationResult {
        pub success: bool,
        pub message: String,
    }

    impl GetAppContainers {
        // 处理获取应用容器请求
        //
        // 目的：枚举所有 UWP 应用并返回其回环状态
        pub fn handle(&self) {
            info!("处理获取应用容器请求");

            match crate::system::loopback::enumerate_app_containers() {
                Ok(containers) => {
                    info!("发送{}个容器信息到 Dart", containers.len());
                    AppContainersList { containers: vec![] }.send_signal_to_dart();

                    for c in containers {
                        AppContainerInfo {
                            app_container_name: c.app_container_name,
                            display_name: c.display_name,
                            package_family_name: c.package_family_name,
                            sid: c.sid,
                            sid_string: c.sid_string,
                            is_loopback_enabled: c.is_loopback_enabled,
                        }
                        .send_signal_to_dart();
                    }

                    // 发送流传输完成信号
                    AppContainersComplete.send_signal_to_dart();
                    info!("应用容器流传输完成");
                }
                Err(e) => {
                    error!("获取应用容器失败：{}", e);
                    AppContainersList { containers: vec![] }.send_signal_to_dart();
                    // 即使失败也发送完成信号，避免 Dart 端无限等待
                    AppContainersComplete.send_signal_to_dart();
                }
            }
        }
    }

    impl SetLoopback {
        // 处理设置回环豁免请求
        //
        // 目的：为单个应用启用或禁用回环豁免
        pub fn handle(self) {
            info!(
                "处理设置回环豁免请求：{} - {}",
                self.package_family_name, self.enabled
            );

            match crate::system::loopback::set_loopback_exemption(
                &self.package_family_name,
                self.enabled,
            ) {
                Ok(()) => {
                    info!("回环豁免设置成功");
                    SetLoopbackResult {
                        success: true,
                        message: "回环豁免设置成功".to_string(),
                    }
                    .send_signal_to_dart();
                }
                Err(e) => {
                    error!("回环豁免设置失败：{}", e);
                    SetLoopbackResult {
                        success: false,
                        message: e,
                    }
                    .send_signal_to_dart();
                }
            }
        }
    }

    impl SaveLoopbackConfiguration {
        // 处理保存配置请求
        //
        // 目的：批量设置多个应用的回环豁免状态
        pub fn handle(self) {
            info!("处理保存配置请求，期望启用{}个容器", self.sid_strings.len());

            // 获取所有容器
            let containers = match crate::system::loopback::enumerate_app_containers() {
                Ok(c) => c,
                Err(e) => {
                    error!("枚举容器失败：{}", e);
                    SaveLoopbackConfigurationResult {
                        success: false,
                        message: format!("无法枚举容器：{}", e),
                    }
                    .send_signal_to_dart();
                    return;
                }
            };

            // 性能优化：使用 HashSet 进行 O(1) 查找，避免 O(n²) 复杂度
            use std::collections::HashSet;
            let enabled_sids: HashSet<&str> = self.sid_strings.iter().map(|s| s.as_str()).collect();

            let mut errors = Vec::new();
            let mut success_count = 0;

            // 对每个容器，检查是否应该启用（现在是 O(1) 查找）
            for container in containers {
                let should_enable = enabled_sids.contains(container.sid_string.as_str());

                if container.is_loopback_enabled != should_enable {
                    info!(
                        "修改容器：{}(SID：{}) | {} -> {}",
                        container.display_name,
                        container.sid_string,
                        container.is_loopback_enabled,
                        should_enable
                    );

                    if let Err(e) = crate::system::loopback::set_loopback_exemption_by_sid(
                        &container.sid,
                        should_enable,
                    ) {
                        error!("设置容器失败：{} - {}", container.display_name, e);
                        errors.push(format!("{}：{}", container.display_name, e));
                    } else {
                        success_count += 1;
                    }
                }
            }

            info!(
                "配置保存完成 | 修改：{} | 错误：{}",
                success_count,
                errors.len()
            );

            if errors.is_empty() {
                SaveLoopbackConfigurationResult {
                    success: true,
                    message: format!("配置保存成功（修改：{}个容器）", success_count),
                }
                .send_signal_to_dart();
            } else {
                SaveLoopbackConfigurationResult {
                    success: false,
                    message: format!(
                        "部分操作失败（成功：{}，失败：{}）：\n{}",
                        success_count,
                        errors.len(),
                        errors.join("\n")
                    ),
                }
                .send_signal_to_dart();
            }
        }
    }
}

#[cfg(target_os = "windows")]
pub use loopback_messages::*;

// ============================================================================
// 应用更新消息协议
// ============================================================================

// 检查应用更新请求
#[derive(Debug, Clone, Serialize, Deserialize, DartSignal)]
pub struct CheckAppUpdateRequest {
    pub current_version: String,
    pub github_repo: String,
}

// 应用更新检查响应
#[derive(Debug, Clone, Serialize, Deserialize, RustSignal)]
pub struct AppUpdateResult {
    pub current_version: String,
    pub latest_version: String,
    pub has_update: bool,
    pub download_url: String,
    pub release_notes: String,
    pub html_url: String,
    pub error: String,
}

impl CheckAppUpdateRequest {
    pub fn handle(&self) {
        let current_version = self.current_version.clone();
        let github_repo = self.github_repo.clone();

        tokio::spawn(async move {
            log::info!("检查更新: {} (当前版本: {})", github_repo, current_version);

            match crate::system::app_update::check_github_update(&current_version, &github_repo)
                .await
            {
                Ok(result) => {
                    log::info!("更新检查成功: 最新版本 {}", result.latest_version);

                    AppUpdateResult {
                        current_version: result.current_version,
                        latest_version: result.latest_version,
                        has_update: result.has_update,
                        download_url: result.download_url.unwrap_or_default(),
                        release_notes: result.release_notes.unwrap_or_default(),
                        html_url: result.html_url.unwrap_or_default(),
                        error: String::new(),
                    }
                    .send_signal_to_dart();
                }
                Err(e) => {
                    log::error!("更新检查失败: {}", e);

                    AppUpdateResult {
                        current_version,
                        latest_version: String::new(),
                        has_update: false,
                        download_url: String::new(),
                        release_notes: String::new(),
                        html_url: String::new(),
                        error: e,
                    }
                    .send_signal_to_dart();
                }
            }
        });
    }
}
