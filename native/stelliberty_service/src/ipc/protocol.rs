// Stelliberty Service IPC 通信协议
//
// 定义客户端和服务端之间的通信协议

use serde::{Deserialize, Serialize};

// IPC 通信路径
#[cfg(windows)]
pub const IPC_PATH: &str = r"\\.\pipe\stelliberty_service";

#[cfg(not(windows))]
pub const IPC_PATH: &str = "/tmp/stelliberty_service.sock";

// 客户端发送给服务的命令
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "data")]
pub enum IpcCommand {
    // 启动 Clash 核心
    StartClash {
        // Clash 核心可执行文件路径
        core_path: String,
        // 配置文件路径
        config_path: String,
        // 数据目录路径（Geodata）
        data_dir: String,
        // 外部控制器地址（HTTP API），空字符串表示禁用
        external_controller: String,
    },

    // 停止 Clash 核心
    StopClash,

    // 获取服务状态
    GetStatus,

    // 获取 Clash 日志（最近 N 行）
    GetLogs {
        lines: usize,
    },

    // 流式获取日志（实时监听）
    StreamLogs,

    // 获取服务版本
    GetVersion,

    // Heartbeat（心跳检测），由主程序定期发送
    Heartbeat,
}

// 服务返回给客户端的响应
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "data")]
pub enum IpcResponse {
    // 操作成功
    Success {
        message: Option<String>,
    },

    // 操作失败
    Error {
        code: i32,
        message: String,
    },

    // 服务状态
    Status {
        // Clash 是否正在运行
        clash_running: bool,
        // Clash 进程 PID
        clash_pid: Option<u32>,
        // 服务启动时间（Unix 时间戳）
        service_uptime: u64,
    },

    // 日志内容
    Logs {
        lines: Vec<String>,
    },

    // 日志流数据（单行）
    LogStream {
        line: String,
    },

    // 版本信息
    Version {
        version: String,
    },

    // HeartbeatAck（心跳响应）
    HeartbeatAck,
}
