// 核心更新分子模块

pub mod updater;

pub use updater::{
    DownloadCoreProgress, DownloadCoreRequest, DownloadCoreResponse, GetLatestCoreVersionRequest,
    GetLatestCoreVersionResponse, ReplaceCoreRequest, ReplaceCoreResponse,
};

pub fn init_listeners() {
    updater::init();
}
