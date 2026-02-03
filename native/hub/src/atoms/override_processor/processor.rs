// 覆写处理器：组合 YAML 合并与 JavaScript 执行能力。
// 提供统一的覆写应用流程。

use super::js_executor::JsExecutor;
use super::yaml_merger::YamlMerger;
use crate::atoms::shared_types::{OverrideConfig, OverrideFormat};

// 覆写处理器
pub struct OverrideProcessor {
    yaml_merger: YamlMerger,
    js_executor: JsExecutor,
}

impl OverrideProcessor {
    // 创建覆写处理器并初始化执行环境。
    pub fn new() -> Result<Self, String> {
        let yaml_merger = YamlMerger::new();
        let js_executor =
            JsExecutor::new().map_err(|e| format!("初始化 JavaScript 引擎失败：{}", e))?;

        Ok(Self {
            yaml_merger,
            js_executor,
        })
    }

    // 按顺序应用覆写并返回最终配置。
    pub fn apply_overrides(
        &mut self,
        base_config: &str,
        overrides: Vec<OverrideConfig>,
    ) -> Result<String, String> {
        let mut current_config = base_config.to_string();

        for (i, override_cfg) in overrides.iter().enumerate() {
            log::info!(
                "[{}] 应用覆写：{}（{:?}）",
                i,
                override_cfg.name,
                override_cfg.format
            );

            current_config = match override_cfg.format {
                OverrideFormat::Yaml => self
                    .yaml_merger
                    .apply(&current_config, &override_cfg.content)
                    .map_err(|e| format!("YAML 覆写失败：{}", e))?,
                OverrideFormat::Javascript => self
                    .js_executor
                    .apply(&current_config, &override_cfg.content)
                    .map_err(|e| format!("JavaScript 覆写失败：{}", e))?,
            };

            log::info!("[{}] 覆写应用成功", i);
        }

        Ok(current_config)
    }
}
