// 系统集成模块：自启动、URL 启动、UWP 回环豁免

use rinf::DartSignal;
use tokio::spawn;

pub mod app_update;
pub mod auto_start;
#[cfg(target_os = "windows")]
pub mod loopback;
pub mod messages;
pub mod url_launcher;

#[allow(unused_imports)]
pub use auto_start::{get_auto_start_status, set_auto_start_status};
#[allow(unused_imports)]
pub use messages::{
    // 应用更新消息
    AppUpdateResult,
    // 自启动消息
    AutoStartStatusResult,
    CheckAppUpdateRequest,
    GetAutoStartStatus,
    // URL 启动消息
    OpenUrl,
    OpenUrlResult,
    SetAutoStartStatus,
};

// UWP 回环豁免消息（仅 Windows）
#[cfg(target_os = "windows")]
#[allow(unused_imports)]
pub use messages::{
    AppContainerInfo, AppContainersComplete, AppContainersList, GetAppContainers,
    SaveLoopbackConfiguration, SaveLoopbackConfigurationResult, SetLoopback, SetLoopbackResult,
};
#[allow(unused_imports)]
pub use url_launcher::open_url;

// 启动消息监听器
fn init_message_listeners() {
    spawn(async {
        let receiver = GetAutoStartStatus::get_dart_signal_receiver();
        while let Some(dart_signal) = receiver.recv().await {
            dart_signal.message.handle();
        }
        log::info!("获取自启动状态消息通道已关闭，退出监听器");
    });

    // 监听设置自启动状态信号
    spawn(async {
        let receiver = SetAutoStartStatus::get_dart_signal_receiver();
        while let Some(dart_signal) = receiver.recv().await {
            dart_signal.message.handle();
        }
        log::info!("设置自启动状态消息通道已关闭，退出监听器");
    });

    // 监听打开 URL 信号
    spawn(async {
        let receiver = OpenUrl::get_dart_signal_receiver();
        while let Some(dart_signal) = receiver.recv().await {
            dart_signal.message.handle();
        }
        log::info!("打开 URL 消息通道已关闭，退出监听器");
    });

    // 监听应用更新检查信号
    spawn(async {
        let receiver = CheckAppUpdateRequest::get_dart_signal_receiver();
        while let Some(dart_signal) = receiver.recv().await {
            dart_signal.message.handle();
        }
        log::info!("应用更新检查消息通道已关闭，退出监听器");
    });
}

// 初始化系统模块
pub fn init() {
    auto_start::init();
    init_message_listeners();

    #[cfg(target_os = "windows")]
    loopback::init();
}
