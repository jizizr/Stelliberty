// 系统代理原子模块

pub mod manager;

// 导出公共接口
pub use manager::{disable_proxy, enable_proxy, get_proxy_info};

pub use manager::init;
