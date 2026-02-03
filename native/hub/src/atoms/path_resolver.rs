// 路径解析原子模块

pub mod resolver;

// 导出公共接口（保持与原 path_service 兼容）
pub use resolver::*;
