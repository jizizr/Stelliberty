// 系统协调器：编排所有系统相关操作

use crate::molecules::system_operations;

pub struct SystemCoordinator;

impl Default for SystemCoordinator {
    fn default() -> Self {
        Self
    }
}

impl SystemCoordinator {
    pub fn new() -> Self {
        Self
    }
}

// 初始化系统协调器
pub fn init() {
    // 初始化分子层监听器（内部会完成必要的原子层初始化）
    system_operations::init_listeners();
}
