// Rust 原生模块入口（为 Flutter 提供系统级功能）
// L1 入口层：负责模块声明和应用生命周期管理

pub mod atoms;
pub mod coordinator;
pub mod molecules;

use rinf::{dart_shutdown, write_interface};

write_interface!();

#[tokio::main(flavor = "current_thread")]
async fn main() {
    // 获取日志文件路径
    let log_path = atoms::path_service::log_file();

    // 初始化日志系统（注入路径，解除原子间依赖）
    atoms::logger::init(log_path);

    // 初始化协调层（内部会初始化所有分子层）
    coordinator::init_all();

    // 等待 Dart 关闭信号
    dart_shutdown().await;

    // 清理资源
    coordinator::cleanup();
}
