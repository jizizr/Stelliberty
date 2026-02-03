// Clash IPC 客户端：通过 Named Pipe（Windows）或 Unix Socket（Unix）通信。
// 使用 Tokio 实现，并手动解析 HTTP 协议。

use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};

#[cfg(unix)]
use tokio::net::UnixStream;

#[cfg(windows)]
use tokio::net::windows::named_pipe::NamedPipeClient;

// HTTP 响应
pub struct HttpResponse {
    pub status_code: u16,
    pub body: String,
}

// IPC 客户端
pub struct IpcClient;

impl IpcClient {
    // 获取默认 IPC 路径
    // Debug/Profile 模式使用 _dev 后缀，避免与 Release 模式冲突
    pub fn default_ipc_path() -> String {
        #[cfg(windows)]
        {
            #[cfg(debug_assertions)]
            {
                r"\\.\pipe\stelliberty_dev".to_string()
            }
            #[cfg(not(debug_assertions))]
            {
                r"\\.\pipe\stelliberty".to_string()
            }
        }

        #[cfg(unix)]
        {
            #[cfg(debug_assertions)]
            {
                "/tmp/stelliberty_dev.sock".to_string()
            }
            #[cfg(not(debug_assertions))]
            {
                "/tmp/stelliberty.sock".to_string()
            }
        }
    }

    // 使用已有连接发送请求（连接池场景）
    #[cfg(windows)]
    pub async fn request_with_connection(
        method: &str,
        path: &str,
        body: Option<&str>,
        mut stream: NamedPipeClient,
    ) -> Result<(HttpResponse, NamedPipeClient), String> {
        // 1. 构建 HTTP 请求
        let request = Self::build_http_request_static(method, path, body);
        log::trace!("发送 IPC 请求：\n{}", request);

        // 2. 发送请求
        stream
            .write_all(request.as_bytes())
            .await
            .map_err(|e| format!("发送请求失败：{}", e))?;

        // 3. 读取响应
        let response = Self::read_http_response_static(&mut stream).await?;

        Ok((response, stream))
    }

    #[cfg(unix)]
    pub async fn request_with_connection(
        method: &str,
        path: &str,
        body: Option<&str>,
        mut stream: UnixStream,
    ) -> Result<(HttpResponse, UnixStream), String> {
        let request = Self::build_http_request_static(method, path, body);
        log::trace!("发送 IPC 请求：\n{}", request);

        stream
            .write_all(request.as_bytes())
            .await
            .map_err(|e| format!("发送请求失败：{}", e))?;

        let response = Self::read_http_response_static(&mut stream).await?;

        Ok((response, stream))
    }

    // 构建 HTTP 请求字符串（静态方法）
    fn build_http_request_static(method: &str, path: &str, body: Option<&str>) -> String {
        let mut request = format!("{} {} HTTP/1.1\r\n", method, path);

        request.push_str("Host: localhost\r\n");

        if let Some(body_str) = body {
            request.push_str("Content-Type: application/json\r\n");
            request.push_str(&format!("Content-Length: {}\r\n", body_str.len()));
            request.push_str("\r\n");
            request.push_str(body_str);
        } else {
            request.push_str("\r\n");
        }

        request
    }

    // 读取 HTTP 响应（静态方法）
    async fn read_http_response_static<S>(stream: &mut S) -> Result<HttpResponse, String>
    where
        S: AsyncReadExt + Unpin,
    {
        let mut reader = BufReader::new(stream);

        // 1. 读取 header
        let mut header_lines = Vec::new();
        loop {
            let mut line = String::new();
            let size = reader
                .read_line(&mut line)
                .await
                .map_err(|e| format!("读取响应行失败：{}", e))?;

            if size == 0 {
                return Err("连接意外关闭".to_string());
            }

            if line == "\r\n" {
                break;
            }

            header_lines.push(line);
        }

        // 2. 解析 status line
        let status_line = header_lines.first().ok_or_else(|| "响应为空".to_string())?;
        let status_code = Self::parse_status_code_static(status_line)?;

        // 3. 解析 headers
        let mut content_length: Option<usize> = None;
        let mut is_chunked = false;

        for line in &header_lines[1..] {
            if let Some((key, value)) = line.split_once(':') {
                let key = key.trim();
                let value = value.trim();

                if key.eq_ignore_ascii_case("content-length") {
                    content_length = value.parse().ok();
                }
                if key.eq_ignore_ascii_case("transfer-encoding") && value.contains("chunked") {
                    is_chunked = true;
                }
            }
        }

        // 4. 读取 body
        let body = if is_chunked {
            Self::read_chunked_body_static(&mut reader).await?
        } else if let Some(length) = content_length {
            let mut body_bytes = vec![0u8; length];
            reader
                .read_exact(&mut body_bytes)
                .await
                .map_err(|e| format!("读取响应体失败：{}", e))?;
            String::from_utf8(body_bytes).map_err(|e| format!("解码响应体失败：{}", e))?
        } else {
            String::new()
        };

        Ok(HttpResponse { status_code, body })
    }

    // 解析 HTTP 状态码（静态方法）
    fn parse_status_code_static(status_line: &str) -> Result<u16, String> {
        let parts: Vec<&str> = status_line.split_whitespace().collect();
        if parts.len() < 2 {
            return Err(format!("无效的状态行：{}", status_line));
        }

        parts[1]
            .parse::<u16>()
            .map_err(|_| format!("无效的状态码：{}", parts[1]))
    }

    // 读取 chunked 编码的响应体（静态方法）
    async fn read_chunked_body_static<R>(reader: &mut BufReader<R>) -> Result<String, String>
    where
        R: AsyncReadExt + Unpin,
    {
        let mut body = Vec::new();

        loop {
            let mut size_line = String::new();
            reader
                .read_line(&mut size_line)
                .await
                .map_err(|e| format!("读取 chunk 大小失败：{}", e))?;

            let size_line = size_line.trim();
            if size_line.is_empty() {
                continue;
            }

            let chunk_size = usize::from_str_radix(size_line, 16)
                .map_err(|e| format!("解析 chunk 大小失败：{}", e))?;

            if chunk_size == 0 {
                let mut end = String::new();
                reader.read_line(&mut end).await.ok();
                break;
            }

            let mut chunk_data = vec![0u8; chunk_size];
            reader
                .read_exact(&mut chunk_data)
                .await
                .map_err(|e| format!("读取 chunk 数据失败：{}", e))?;
            body.extend_from_slice(&chunk_data);

            let mut crlf = String::new();
            reader.read_line(&mut crlf).await.ok();
        }

        String::from_utf8(body).map_err(|e| format!("解码 chunked body 失败：{}", e))
    }
}
