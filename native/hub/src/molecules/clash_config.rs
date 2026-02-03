// Clash 配置管理分子模块

pub mod generator;
pub mod injector;
pub mod runtime_params;

pub use generator::{GenerateRuntimeConfigRequest, GenerateRuntimeConfigResponse};
pub use injector::inject_runtime_params;
pub use runtime_params::RuntimeConfigParams;

pub fn init_listeners() {
    generator::init();
}
