// 网络接口原子模块

pub mod detector;

// 导出公共接口
pub use detector::{
    GetNetworkInterfaces, NetworkInterfacesInfo, get_hostname, get_network_addresses,
};

pub use detector::init;
