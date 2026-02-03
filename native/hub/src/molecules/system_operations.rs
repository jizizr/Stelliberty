// 系统操作分子模块

use crate::atoms::{network_interfaces, system_proxy};

pub mod app_update;
pub mod auto_start;
pub mod backup;
#[cfg(windows)]
pub mod loopback;
pub mod power_event;
pub mod url_launcher;

pub use app_update::{AppUpdateResult, CheckAppUpdateRequest};
pub use auto_start::{AutoStartStatusResult, GetAutoStartStatus, SetAutoStartStatus};
pub use backup::{BackupOperationResult, CreateBackupRequest, RestoreBackupRequest};

#[cfg(windows)]
pub use loopback::{
    AppContainerInfo, AppContainersComplete, GetAppContainers, SaveLoopbackConfiguration,
    SaveLoopbackConfigurationResult, SetLoopback, SetLoopbackResult,
};
pub use power_event::{
    PowerEventType, SystemPowerEvent, start_power_event_listener, stop_power_event_listener,
};
pub use url_launcher::{OpenUrl, OpenUrlResult};

pub fn init_listeners() {
    system_proxy::init();
    network_interfaces::init();

    app_update::init();
    auto_start::init();
    backup::init();
    #[cfg(windows)]
    loopback::init();
    url_launcher::init();

    power_event::start_power_event_listener();
}
