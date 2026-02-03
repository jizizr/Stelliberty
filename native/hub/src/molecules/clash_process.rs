// Clash 进程管理分子模块

pub mod process_manager;

#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
pub mod service_manager;

pub use process_manager::{ClashProcessResult, StartClashProcess, StopClashProcess};

#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
pub use service_manager::ServiceManager;

pub fn init_listeners() {
    process_manager::init();

    #[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
    service_manager::init();
}

pub fn cleanup() {
    process_manager::cleanup();
}
