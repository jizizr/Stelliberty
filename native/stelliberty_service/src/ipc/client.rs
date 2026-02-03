// IPC 客户端实现
//
// 预留给 Flutter 端使用

use super::error::{IpcError, Result};
use super::protocol::{IPC_PATH, IpcCommand, IpcResponse};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::time::timeout;

// IPC 客户端
pub struct IpcClient {
    // 超时时间
    timeout: Duration,
    // 最大重试次数
    max_retries: usize,
}

impl Default for IpcClient {
    fn default() -> Self {
        Self {
            timeout: Duration::from_secs(5),
            max_retries: 3,
        }
    }
}

impl IpcClient {
    // 创建新的 IPC 客户端
    pub fn new() -> Self {
        Self::default()
    }

    // 设置超时时间
    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    // 设置最大重试次数
    pub fn with_max_retries(mut self, max_retries: usize) -> Self {
        self.max_retries = max_retries;
        self
    }

    // 发送命令并等待响应
    pub async fn send_command(&self, command: IpcCommand) -> Result<IpcResponse> {
        let mut last_error: Option<IpcError> = None;

        for attempt in 0..=self.max_retries {
            if attempt > 0 {
                log::debug!("重试 IPC 连接，尝试 {}/{}", attempt, self.max_retries);
                tokio::time::sleep(Duration::from_millis(100 * attempt as u64)).await;
            }

            match self.try_send_command(&command).await {
                Ok(response) => {
                    // 检查是否是错误响应
                    if let IpcResponse::Error { code, message } = response {
                        return Err(IpcError::ServiceError(code, message));
                    }
                    return Ok(response);
                }
                Err(e) => {
                    log::debug!(
                        "IPC 通信失败（尝试 {}/{}）: {}",
                        attempt + 1,
                        self.max_retries + 1,
                        e
                    );
                    last_error = Some(e);
                }
            }
        }

        match last_error {
            Some(e) => Err(e),
            None => Err(IpcError::Other("IPC 通信失败".to_string())),
        }
    }

    // 尝试发送命令（单次）
    async fn try_send_command(&self, command: &IpcCommand) -> Result<IpcResponse> {
        // 序列化命令
        let command_json = serde_json::to_string(command)?;
        let command_bytes = command_json.as_bytes();

        // 连接到服务
        let mut stream = timeout(self.timeout, self.connect())
            .await
            .map_err(|_| IpcError::Timeout)??;

        // 发送命令长度（4 字节）+ 命令数据
        let len = command_bytes.len() as u32;
        stream.write_all(&len.to_le_bytes()).await?;
        stream.write_all(command_bytes).await?;
        stream.flush().await?;

        // 读取响应长度
        let mut len_buf = [0u8; 4];
        timeout(self.timeout, stream.read_exact(&mut len_buf))
            .await
            .map_err(|_| IpcError::Timeout)??;
        let response_len = u32::from_le_bytes(len_buf) as usize;

        // 防止恶意响应占用过多内存
        if response_len > 10 * 1024 * 1024 {
            // 最大 10MB
            return Err(IpcError::Other("响应数据过大".to_string()));
        }

        // 读取响应数据
        let mut response_buf = vec![0u8; response_len];
        timeout(self.timeout, stream.read_exact(&mut response_buf))
            .await
            .map_err(|_| IpcError::Timeout)??;

        // 反序列化响应
        let response: IpcResponse = serde_json::from_slice(&response_buf)?;
        Ok(response)
    }

    // 连接到服务
    #[cfg(windows)]
    async fn connect(&self) -> Result<tokio::net::windows::named_pipe::NamedPipeClient> {
        use tokio::net::windows::named_pipe::ClientOptions;

        ClientOptions::new()
            .open(IPC_PATH)
            .map_err(|e| IpcError::ConnectionFailed(format!("无法连接到服务: {e}")))
    }

    // 连接到服务
    #[cfg(not(windows))]
    async fn connect(&self) -> Result<tokio::net::UnixStream> {
        use tokio::net::UnixStream;

        UnixStream::connect(IPC_PATH)
            .await
            .map_err(|e| IpcError::ConnectionFailed(format!("无法连接到服务: {}", e)))
    }

    // 检查服务是否在运行（快速检测）
    pub async fn is_service_running(&self) -> bool {
        matches!(
            timeout(
                Duration::from_millis(500),
                self.send_command(IpcCommand::Heartbeat)
            )
            .await,
            Ok(Ok(IpcResponse::HeartbeatAck))
        )
    }

    // 订阅日志流（持续接收日志，直到连接断开或返回错误）
    // 参数 callback: 每收到一行日志时调用，返回 false 表示停止接收
    pub async fn stream_logs<F>(&self, mut callback: F) -> Result<()>
    where
        F: FnMut(String) -> bool,
    {
        // 序列化 StreamLogs 命令
        let command = IpcCommand::StreamLogs;
        let command_json = serde_json::to_string(&command)?;
        let command_bytes = command_json.as_bytes();

        // 连接到服务
        let mut stream = timeout(self.timeout, self.connect())
            .await
            .map_err(|_| IpcError::Timeout)??;

        // 发送命令长度 + 命令数据
        let len = command_bytes.len() as u32;
        stream.write_all(&len.to_le_bytes()).await?;
        stream.write_all(command_bytes).await?;
        stream.flush().await?;

        // 读取初始响应（应该是 Success）
        let mut len_buf = [0u8; 4];
        timeout(self.timeout, stream.read_exact(&mut len_buf))
            .await
            .map_err(|_| IpcError::Timeout)??;
        let response_len = u32::from_le_bytes(len_buf) as usize;

        if response_len > 10 * 1024 * 1024 {
            return Err(IpcError::Other("响应数据过大".to_string()));
        }

        let mut response_buf = vec![0u8; response_len];
        timeout(self.timeout, stream.read_exact(&mut response_buf))
            .await
            .map_err(|_| IpcError::Timeout)??;

        let initial_response: IpcResponse = serde_json::from_slice(&response_buf)?;

        // 确认初始响应是成功
        match initial_response {
            IpcResponse::Success { .. } => {
                // 继续接收日志流
            }
            IpcResponse::Error { code, message } => {
                return Err(IpcError::ServiceError(code, message));
            }
            _ => {
                return Err(IpcError::Other("意外的初始响应类型".to_string()));
            }
        }

        // 持续接收日志流
        loop {
            // 读取日志响应长度
            let mut len_buf = [0u8; 4];
            match stream.read_exact(&mut len_buf).await {
                Ok(_) => {}
                Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                    // 连接关闭，正常退出
                    break;
                }
                Err(e) => {
                    return Err(e.into());
                }
            }

            let log_len = u32::from_le_bytes(len_buf) as usize;

            // 防止恶意响应
            if log_len > 1024 * 1024 {
                return Err(IpcError::Other("单条日志数据过大".to_string()));
            }

            // 读取日志数据
            let mut log_buf = vec![0u8; log_len];
            stream.read_exact(&mut log_buf).await?;

            // 反序列化日志响应
            let log_response: IpcResponse = serde_json::from_slice(&log_buf)?;

            match log_response {
                IpcResponse::LogStream { line } => {
                    // 调用回调函数，如果返回 false 则停止接收
                    if !callback(line) {
                        break;
                    }
                }
                IpcResponse::Error { code, message } => {
                    return Err(IpcError::ServiceError(code, message));
                }
                _ => {
                    return Err(IpcError::Other("意外的日志流响应类型".to_string()));
                }
            }
        }

        Ok(())
    }
}
