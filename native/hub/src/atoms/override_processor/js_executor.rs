// JavaScript 覆写执行器：负责在 QuickJS 中执行覆写脚本并返回结果。
// 入口约定： main(config) 返回可 JSON 序列化的配置对象。

use serde_json::Value as JsonValue;
use serde_yaml_ng::Value as YamlValue;

#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
use rquickjs::{Context, Runtime};

// JavaScript 执行器
pub struct JsExecutor {
    #[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
    runtime: Runtime,
    #[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
    context: Context,
}

impl JsExecutor {
    // 创建 JavaScript 执行器并初始化 QuickJS 上下文。
    #[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
    pub fn new() -> Result<Self, String> {
        let runtime = Runtime::new().map_err(|e| format!("初始化 JavaScript 运行时失败：{}", e))?;
        let context =
            Context::full(&runtime).map_err(|e| format!("初始化 JavaScript 上下文失败：{}", e))?;

        Ok(Self { runtime, context })
    }

    #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
    pub fn new() -> Result<Self, String> {
        Ok(Self {})
    }

    // 应用 JavaScript 覆写：YAML 转 JSON，执行 main(config)，再转换为 YAML。
    // 返回覆写后的配置内容。
    #[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
    pub fn apply(&mut self, base_content: &str, js_code: &str) -> Result<String, String> {
        log::info!("JavaScript 覆写开始");
        log::info!("基础配置长度：{}字节", base_content.len());
        log::info!("JS 脚本长度：{}字节", js_code.len());

        // 1. 解析 YAML 转 JSON
        let yaml_val: YamlValue = serde_yaml_ng::from_str(base_content).map_err(|e| {
            log::error!("解析 YAML 配置失败：{}", e);
            format!("解析配置失败：{}", e)
        })?;

        let json_val: JsonValue = serde_json::to_value(&yaml_val).map_err(|e| {
            log::error!("转换为 JSON 失败：{}", e);
            format!("转换为 JSON 失败：{}", e)
        })?;

        let config_json = serde_json::to_string(&json_val).map_err(|e| {
            log::error!("序列化 JSON 失败：{}", e);
            format!("序列化 JSON 失败：{}", e)
        })?;

        log::info!("YAML 转 JSON 成功，JSON 长度：{}字节", config_json.len());

        // 检查 proxies 字段
        if let Some(proxies) = json_val.get("proxies") {
            if let Some(arr) = proxies.as_array() {
                log::info!("配置中包含{}个代理节点", arr.len());
                if let Some(first_proxy) = arr.first() {
                    log::info!(
                        "  第一个代理节点：{}",
                        serde_json::to_string(first_proxy).unwrap_or_default()
                    );
                }
            }
        } else {
            log::warn!("配置中未找到 proxies 字段");
        }

        // 转义 JSON 字符串中的反斜杠和单引号，以便安全地嵌入 JavaScript
        let escaped_config = config_json.replace('\\', "\\\\").replace('\'', "\\'");

        // 2. 构建完整的 JavaScript 代码
        // 用户脚本必须定义 main(config) 函数
        let full_js_code = format!(
            r#"
            (function() {{
                // 用户的覆写代码（定义 main 函数）
                {}

                // 初始化配置对象（从基础配置的 JSON）
                var config = JSON.parse('{}');

                // 调用 main 函数并传入配置
                if (typeof main === 'function') {{
                    config = main(config);
                }} else {{
                    throw new Error('覆写脚本必须定义 main(config) 函数');
                }}

                // 返回修改后的配置
                return JSON.stringify(config);
            }})()
            "#,
            js_code, escaped_config
        );

        log::info!(
            "JavaScript 代码构建完成，总长度：{}字节",
            full_js_code.len()
        );

        // 3. 执行 JavaScript
        log::info!("开始执行 JavaScript");
        let result_str = self.execute_js(&full_js_code).map_err(|e| {
            log::error!("JavaScript 执行失败：{}", e);
            e
        })?;

        log::info!("JavaScript 执行成功");
        log::info!("JavaScript 结果长度：{}字节", result_str.len());

        // 4. JSON 转 YAML
        let json_result: JsonValue = serde_json::from_str(&result_str).map_err(|e| {
            log::error!("解析 JavaScript 结果失败：{}", e);
            log::error!("错误的 JSON 内容：{}", result_str);
            format!("解析 JavaScript 结果失败：{}", e)
        })?;

        log::info!("JSON 解析成功");

        // 检查返回的 proxies 字段
        if let Some(proxies) = json_result.get("proxies") {
            if let Some(arr) = proxies.as_array() {
                log::info!("返回的配置中包含{}个代理节点", arr.len());
                if let Some(first_proxy) = arr.first() {
                    log::info!(
                        "  返回的第一个代理节点：{}",
                        serde_json::to_string(first_proxy).unwrap_or_default()
                    );
                }
            }
        } else {
            log::warn!("返回的配置中未找到 proxies 字段");
        }

        let yaml_result: YamlValue = serde_json::from_value(json_result).map_err(|e| {
            log::error!("转换为 YAML 失败：{}", e);
            format!("转换为 YAML 失败：{}", e)
        })?;

        let final_yaml = serde_yaml_ng::to_string(&yaml_result).map_err(|e| {
            log::error!("序列化 YAML 失败：{}", e);
            format!("序列化 YAML 失败：{}", e)
        })?;

        log::info!("YAML 序列化成功，最终长度：{} 字节", final_yaml.len());

        log::info!("JavaScript 覆写成功");
        Ok(final_yaml)
    }

    #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
    pub fn apply(&mut self, _base_content: &str, _js_code: &str) -> Result<String, String> {
        Err("当前平台不支持 JavaScript 覆写".to_string())
    }

    #[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
    fn execute_js(&self, full_js_code: &str) -> Result<String, String> {
        // 保持运行时生命周期，避免上下文提前释放
        let _runtime = &self.runtime;
        self.context
            .with(|ctx| ctx.eval::<String, _>(full_js_code))
            .map_err(|e| format!("JavaScript 执行失败：{}", e))
    }
}
