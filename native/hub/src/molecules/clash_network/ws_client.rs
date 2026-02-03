// WebSocket over IPC 客户端
// 通过 Named Pipe/Unix Socket 建立 WebSocket 连接

use super::connection;
use base64::Engine;
use futures_util::stream::StreamExt;
use std::collections::HashMap;
use std::sync::Arc;
use tokio_tungstenite::{client_async, tungstenite::protocol::Message};

#[cfg(unix)]
use tokio::net::UnixStream;

#[cfg(windows)]
use tokio::net::windows::named_pipe::NamedPipeClient;

// HTTP Request 构建器 (来自 http crate)
use http::Request;
use http::header::{CONNECTION, HOST, SEC_WEBSOCKET_KEY, SEC_WEBSOCKET_VERSION, UPGRADE};

// WebSocket 连接 ID
pub type ConnectionId = u32;

// WebSocket 客户端
pub struct WebSocketClient {
    ipc_path: String,
    next_connection_id: Arc<tokio::sync::Mutex<u32>>,
    // 存储活跃的连接任务，用于断开连接
    connections: Arc<tokio::sync::Mutex<HashMap<ConnectionId, tokio::task::JoinHandle<()>>>>,
}

impl WebSocketClient {
    // 创建新的 WebSocket 客户端
    pub fn new(ipc_path: String) -> Self {
        Self {
            ipc_path,
            next_connection_id: Arc::new(tokio::sync::Mutex::new(1)),
            connections: Arc::new(tokio::sync::Mutex::new(HashMap::new())),
        }
    }

    // 生成 WebSocket Key（符合 RFC 6455）
    fn generate_websocket_key() -> String {
        // RFC 6455 要求：16 字节随机数据的 base64 编码
        use rand::RngCore;
        let mut key_bytes = [0u8; 16];
        rand::rng().fill_bytes(&mut key_bytes);
        base64::engine::general_purpose::STANDARD.encode(key_bytes)
    }

    // 连接到 WebSocket 端点并开始接收消息。
    // 返回连接 ID，用于后续管理与断开连接。
    pub async fn connect<F>(&self, endpoint: &str, on_message: F) -> Result<ConnectionId, String>
    where
        F: Fn(serde_json::Value) + Send + 'static,
    {
        log::debug!("开始建立 WebSocket 连接：{}", endpoint);

        // 1. 分配连接 ID
        let connection_id = {
            let mut id_guard = self.next_connection_id.lock().await;
            let id = *id_guard;
            *id_guard += 1;
            id
        };

        // 2. 连接到 IPC 端点
        #[cfg(windows)]
        let stream = self.connect_windows().await?;

        #[cfg(unix)]
        let stream = self.connect_unix().await?;

        // 3. 构造 WebSocket 握手请求（使用 http::Request）
        // 关键：使用 ws:// scheme 以通过 tungstenite 的 URI 验证
        let uri = format!("ws://localhost{}", endpoint);
        log::trace!("构造 URI：{}", uri);

        let request = Request::builder()
            .uri(&uri)
            .header(HOST, "stelliberty")
            .header(SEC_WEBSOCKET_KEY, Self::generate_websocket_key())
            .header(CONNECTION, "Upgrade")
            .header(UPGRADE, "websocket")
            .header(SEC_WEBSOCKET_VERSION, "13")
            .body(())
            .map_err(|e| format!("构造 WebSocket 请求失败：{}", e))?;

        log::trace!("WebSocket 请求构造成功，URI：{:?}", request.uri());

        log::trace!("发送 WebSocket 握手请求：{}", endpoint);

        // 4. 使用 client_async 建立 WebSocket 连接
        let (ws_stream, _) = client_async(request, stream)
            .await
            .map_err(|e| format!("WebSocket 握手失败：{}", e))?;

        log::info!("WebSocket 连接建立成功[{}]：{}", connection_id, endpoint);

        // 5. 分离读写流
        let (_writer, mut reader) = ws_stream.split();

        // 6. 启动消息接收循环
        let connections = self.connections.clone();
        let handle = tokio::spawn(async move {
            log::trace!("WebSocket 消息接收循环已启动 [{}]", connection_id);

            while let Some(message) = reader.next().await {
                match message {
                    Ok(Message::Text(text)) => {
                        // 解析 JSON 消息
                        match serde_json::from_str::<serde_json::Value>(&text) {
                            Ok(json_value) => {
                                log::trace!(
                                    "WebSocket 收到消息[{}]：{}bytes",
                                    connection_id,
                                    text.len()
                                );
                                on_message(json_value);
                            }
                            Err(e) => {
                                log::error!(
                                    "WebSocket 消息 JSON 解析失败[{}]：{}",
                                    connection_id,
                                    e
                                );
                            }
                        }
                    }
                    Ok(Message::Close(close_frame)) => {
                        log::info!("WebSocket 连接关闭[{}]：{:?}", connection_id, close_frame);
                        break;
                    }
                    Ok(Message::Ping(_)) | Ok(Message::Pong(_)) => {
                        // Ping/Pong 由 tokio-tungstenite 自动处理
                    }
                    Ok(Message::Binary(data)) => {
                        log::debug!(
                            "WebSocket 收到二进制消息[{}]：{}bytes",
                            connection_id,
                            data.len()
                        );
                    }
                    Ok(Message::Frame(_)) => {
                        // 忽略原始帧
                    }
                    Err(e) => {
                        log::error!("WebSocket 消息读取错误[{}]：{}", connection_id, e);
                        break;
                    }
                }
            }

            log::debug!("WebSocket 消息接收循环已结束[{}]", connection_id);

            // 连接结束后，从连接表中移除
            let mut conns = connections.lock().await;
            conns.remove(&connection_id);
        });

        // 存储连接句柄
        {
            let mut conns = self.connections.lock().await;
            conns.insert(connection_id, handle);
        }

        Ok(connection_id)
    }

    // 断开指定的 WebSocket 连接
    pub async fn disconnect(&self, connection_id: ConnectionId) {
        let mut conns = self.connections.lock().await;

        if let Some(handle) = conns.remove(&connection_id) {
            log::info!("正在断开 WebSocket 连接[{}]", connection_id);
            handle.abort();
            log::info!("WebSocket 连接已断开[{}]", connection_id);
        } else {
            log::warn!("尝试断开不存在的连接[{}]", connection_id);
        }
    }

    // 断开所有 WebSocket 连接
    #[allow(dead_code)]
    pub async fn disconnect_all(&self) {
        let mut conns = self.connections.lock().await;

        let count = conns.len();
        if count > 0 {
            log::info!("正在断开所有 WebSocket 连接（共{}个）", count);

            for (id, handle) in conns.drain() {
                log::debug!("断开连接[{}]", id);
                handle.abort();
            }

            log::info!("所有 WebSocket 连接已断开");
        }
    }

    // Windows: 连接到 Named Pipe
    #[cfg(windows)]
    async fn connect_windows(&self) -> Result<NamedPipeClient, String> {
        connection::connect_named_pipe(&self.ipc_path).await
    }

    // Unix: 连接到 Unix Socket
    #[cfg(unix)]
    async fn connect_unix(&self) -> Result<UnixStream, String> {
        connection::connect_unix_socket(&self.ipc_path).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_websocket_key_generation() {
        let key1 = WebSocketClient::generate_websocket_key();
        let key2 = WebSocketClient::generate_websocket_key();

        // 每次生成的 key 应该不同
        assert_ne!(key1, key2);

        // key 应该是 base64 编码的
        assert!(
            base64::engine::general_purpose::STANDARD
                .decode(&key1)
                .is_ok()
        );
    }

    #[test]
    fn test_connection_id_increment() {
        let client = WebSocketClient::new(String::from("test"));

        // 验证初始 ID 从 1 开始
        assert_eq!(*client.next_connection_id.blocking_lock(), 1);
    }
}
