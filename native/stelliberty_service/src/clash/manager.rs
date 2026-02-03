// Clash 核心进程管理器

use std::process::{Child, Command, Stdio};
use std::sync::Mutex;

// Clash 进程状态
#[derive(Debug, Clone)]
pub struct ClashStatus {
    // 是否正在运行
    pub is_running: bool,
    // 进程 PID
    pub pid: Option<u32>,
    // 运行时长（秒）
    pub uptime: u64,
}

// Clash 管理器
pub struct ClashManager {
    // Clash 核心路径
    core_path: Option<String>,
    // 配置文件路径
    config_path: Option<String>,
    // 数据目录
    data_dir: Option<String>,
    // API 主机
    api_host: Option<String>,
    // API 端口
    api_port: Option<u16>,
    // 子进程句柄（使用 Mutex 实现内部可变性）
    child: Mutex<Option<Child>>,
    // 启动时间
    start_time: Mutex<Option<std::time::Instant>>,
}

impl Default for ClashManager {
    fn default() -> Self {
        Self {
            core_path: None,
            config_path: None,
            data_dir: None,
            api_host: None,
            api_port: None,
            child: Mutex::new(None),
            start_time: Mutex::new(None),
        }
    }
}

impl ClashManager {
    // 创建新的管理器
    pub fn new() -> Self {
        Self::default()
    }

    // 启动 Clash 核心
    pub fn start(
        &mut self,
        core_path: String,
        config_path: String,
        data_dir: String,
        external_controller: String,
    ) -> Result<(), String> {
        // 如果已经在运行，先停止
        if self.is_running() {
            log::info!("Clash 已在运行，先停止旧实例");
            self.stop()?;
        }

        if let Err(e) = Self::cleanup_orphan_processes() {
            log::warn!("清理孤立进程失败：{}", e);
        }

        log::info!("启动 Clash 核心");
        log::info!("核心路径: {}", core_path);
        log::info!("配置文件: {}", config_path);
        log::info!("数据目录: {}", data_dir);
        log::info!(
            "外部控制器: {}",
            if external_controller.is_empty() {
                "禁用"
            } else {
                &external_controller
            }
        );

        // 检查核心文件是否存在
        if !std::path::Path::new(&core_path).exists() {
            let error_msg = format!(
                "Clash 核心文件不存在\n路径: {}\n提示: 请检查核心文件是否正确安装",
                core_path
            );
            log::error!("{}", error_msg);
            return Err(error_msg);
        }

        // 检查配置文件是否存在
        if !std::path::Path::new(&config_path).exists() {
            let error_msg = format!(
                "配置文件不存在\n路径: {}\n提示: 请检查配置文件是否正确生成",
                config_path
            );
            log::error!("{}", error_msg);
            return Err(error_msg);
        }

        // 构建启动参数
        let mut args = vec![
            "-d".to_string(),
            data_dir.clone(),
            "-f".to_string(),
            config_path.clone(),
        ];

        // 添加 external-controller 参数
        // 无论是否启用，都必须传递此参数
        // 空字符串表示禁用 HTTP API
        args.push("-ext-ctl".to_string());
        args.push(external_controller.clone());

        log::debug!("Clash 启动参数: {:?}", args);

        // 启动进程，重定向输出防止缓冲区阻塞
        let child = Command::new(&core_path)
            .args(&args)
            .stdout(Stdio::null()) // 防止输出缓冲区填满导致进程阻塞
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| {
                let error_msg = format!(
                    "启动 Clash 失败: {}\n核心路径: {}\n配置文件: {}\n数据目录: {}\n外部控制器: {}\n{}",
                    e,
                    core_path,
                    config_path,
                    data_dir,
                    if external_controller.is_empty() { "禁用" } else { &external_controller },
                    Self::format_io_error_hint(&e)
                );
                log::error!("{}", error_msg);
                error_msg
            })?;

        let pid = child.id();

        self.core_path = Some(core_path);
        self.config_path = Some(config_path);
        self.data_dir = Some(data_dir);
        self.api_host = None;
        self.api_port = None;

        *self.child.lock().unwrap_or_else(|e| {
            log::warn!("Child 锁中毒，正在恢复");
            e.into_inner()
        }) = Some(child);
        *self.start_time.lock().unwrap_or_else(|e| {
            log::warn!("StartTime 锁中毒，正在恢复");
            e.into_inner()
        }) = Some(std::time::Instant::now());

        log::info!("Clash 核心已启动，PID: {}", pid);
        Ok(())
    }

    // 强制停止 Clash（Windows 使用 taskkill）
    #[cfg(windows)]
    fn force_kill_windows(pid: u32) -> Result<(), String> {
        log::warn!("使用强制终止方式清理进程 PID={}", pid);

        // 使用 taskkill /F /T 强制终止进程树
        let output = Command::new("taskkill")
            .args(["/F", "/T", "/PID", &pid.to_string()])
            .output()
            .map_err(|e| format!("执行 taskkill 失败: {}", e))?;

        if output.status.success() {
            log::info!("进程 PID={} 已被强制终止", pid);
            Ok(())
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr);
            Err(format!("taskkill 失败: {}", stderr))
        }
    }

    // 强制停止 Clash（Unix 平台使用信号机制，优先安全退出）
    #[cfg(unix)]
    fn force_kill_unix(pid: u32) -> Result<(), String> {
        use nix::sys::signal::{Signal, kill};
        use nix::unistd::Pid;
        use std::thread;
        use std::time::{Duration, Instant};

        log::warn!("使用强制终止方式清理进程 PID={}", pid);

        let nix_pid = Pid::from_raw(pid as i32);

        // 步骤 1：优先尝试安全退出（发送 SIGTERM 信号）
        log::debug!("发送 SIGTERM 信号到 PID={}", pid);
        if let Err(e) = kill(nix_pid, Signal::SIGTERM) {
            return Err(format!("发送 SIGTERM 失败: {}", e));
        }

        // 步骤 2：动态超时等待进程安全退出
        // 轮询策略：初期高频探测（50ms 间隔），300ms 后降低轮询频率（100ms 间隔），最多等待 1 秒
        let start = Instant::now();
        let max_wait = Duration::from_secs(1);
        let mut check_interval = Duration::from_millis(50);

        while start.elapsed() < max_wait {
            thread::sleep(check_interval);

            // 探测进程存活状态（使用 signal 0 探测，不实际发送信号）
            match kill(nix_pid, None) {
                Err(_) => {
                    // 进程已终止
                    log::info!(
                        "进程 PID={} 已安全退出（耗时 {}ms）",
                        pid,
                        start.elapsed().as_millis()
                    );
                    return Ok(());
                }
                Ok(_) => {
                    // 进程仍在运行，继续轮询
                    // 超过 300ms 后降低轮询频率以减少 CPU 开销
                    if start.elapsed() > Duration::from_millis(300) {
                        check_interval = Duration::from_millis(100);
                    }
                    continue;
                }
            }
        }

        // 步骤 3：超时后使用 SIGKILL 强制终止
        log::warn!(
            "安全退出超时（{}ms），发送 SIGKILL 信号到 PID={}",
            start.elapsed().as_millis(),
            pid
        );
        if let Err(e) = kill(nix_pid, Signal::SIGKILL) {
            return Err(format!("发送 SIGKILL 失败: {}", e));
        }

        // 等待进程回收确认（SIGKILL 通常立即生效）
        thread::sleep(Duration::from_millis(100));
        match kill(nix_pid, None) {
            Err(_) => {
                log::info!("进程 PID={} 已被强制终止", pid);
                Ok(())
            }
            Ok(_) => Err(format!("进程 PID={} 在 SIGKILL 后仍然存在", pid)),
        }
    }

    // 检查并清理孤立的 Clash 核心进程
    // 应用场景：处理心跳超时清理失败导致的僵尸进程（进程句柄丢失但进程仍在后台运行）
    fn cleanup_orphan_processes() -> Result<(), String> {
        #[cfg(windows)]
        {
            // 使用 tasklist 查找 clash-core.exe 进程
            let output = Command::new("tasklist")
                .args(["/FI", "IMAGENAME eq clash-core.exe", "/FO", "CSV", "/NH"])
                .stdout(Stdio::piped())
                .output()
                .map_err(|e| format!("执行 tasklist 失败: {}", e))?;

            if !output.status.success() {
                return Err("tasklist 执行失败".to_string());
            }

            let stdout = String::from_utf8_lossy(&output.stdout);

            // 解析 CSV 输出格式："clash-core.exe","1234","Console","1","12,345 K"
            for line in stdout.lines() {
                if line.contains("clash-core.exe") {
                    // 提取 PID（第二列）
                    let parts: Vec<&str> = line.split(',').collect();
                    if parts.len() >= 2 {
                        let pid_str = parts[1].trim_matches('"').trim();
                        if let Ok(pid) = pid_str.parse::<u32>() {
                            log::warn!("检测到孤立的 clash-core.exe 进程 PID={}，正在清理", pid);
                            if let Err(e) = Self::force_kill_windows(pid) {
                                log::error!("清理孤立进程 PID={} 失败: {}", pid, e);
                            }
                        }
                    }
                }
            }

            Ok(())
        }

        #[cfg(unix)]
        {
            // 使用 pgrep 查找 clash-core 进程
            let output = Command::new("pgrep")
                .arg("clash-core")
                .stdout(Stdio::piped())
                .output()
                .map_err(|e| format!("执行 pgrep 失败: {}", e))?;

            // pgrep 返回 0 表示找到进程，1 表示未找到
            if output.status.code() == Some(1) {
                // 未找到进程，正常情况
                return Ok(());
            }

            if !output.status.success() {
                return Err(format!("pgrep 执行失败: 退出码 {:?}", output.status.code()));
            }

            let stdout = String::from_utf8_lossy(&output.stdout);

            // 每行是一个 PID
            for line in stdout.lines() {
                if let Ok(pid) = line.trim().parse::<u32>() {
                    log::warn!("检测到孤立的 clash-core 进程 PID={}，正在清理", pid);
                    if let Err(e) = Self::force_kill_unix(pid) {
                        log::error!("清理孤立进程 PID={} 失败: {}", pid, e);
                    }
                }
            }

            Ok(())
        }
    }

    // 停止 Clash 核心（改进版：带强制清理）
    pub fn stop(&mut self) -> Result<(), String> {
        let mut child_guard = self.child.lock().unwrap_or_else(|e| {
            log::warn!("Child 锁中毒，正在恢复");
            e.into_inner()
        });

        if let Some(mut child) = child_guard.take() {
            let pid = child.id();
            log::info!("停止 Clash 核心 (PID: {})", pid);

            // 先尝试优雅停止
            match child.kill() {
                Ok(_) => {
                    log::debug!("已发送 kill 信号到 PID={}", pid);

                    // 在子线程中等待，避免阻塞
                    let wait_handle = std::thread::spawn(move || child.wait());

                    // 等待最多 3 秒
                    let wait_result = wait_handle.join_timeout(std::time::Duration::from_secs(3));

                    match wait_result {
                        Ok(Ok(Ok(_))) => {
                            log::info!("Clash 核心已正常停止 (PID: {})", pid);
                        }
                        Ok(Ok(Err(e))) => {
                            log::warn!("等待进程退出失败: {}, 尝试强制清理", e);
                            #[cfg(windows)]
                            {
                                let _ = Self::force_kill_windows(pid);
                            }
                        }
                        Ok(Err(_)) => {
                            log::error!("等待进程超时 (3 秒)，强制清理 PID={}", pid);
                            #[cfg(windows)]
                            {
                                let _ = Self::force_kill_windows(pid);
                            }
                        }
                        Err(_) => {
                            log::error!("等待进程线程 panic，尝试强制清理 PID={}", pid);
                            #[cfg(windows)]
                            {
                                let _ = Self::force_kill_windows(pid);
                            }
                        }
                    }
                }
                Err(e) => {
                    log::error!("发送 kill 信号失败: {}, 尝试强制清理", e);
                    #[cfg(windows)]
                    {
                        let _ = Self::force_kill_windows(pid);
                    }
                    #[cfg(not(windows))]
                    {
                        let error_msg = format!(
                            "停止 Clash 失败 (PID: {}): {}\n{}",
                            pid,
                            e,
                            Self::format_io_error_hint(&e)
                        );
                        log::error!("{}", error_msg);
                        return Err(error_msg);
                    }
                }
            }

            // 清空状态
            *self.start_time.lock().unwrap_or_else(|e| {
                log::warn!("StartTime 锁中毒，正在恢复");
                e.into_inner()
            }) = None;
        } else {
            log::debug!("Clash 未运行，无需停止");
        }

        Ok(())
    }

    // 检查 Clash 是否正在运行（不需要可变引用，支持并发读）
    pub fn is_running(&self) -> bool {
        let mut child_guard = self.child.lock().unwrap_or_else(|e| {
            log::warn!("Child 锁中毒，正在恢复");
            e.into_inner()
        });

        if let Some(child) = child_guard.as_mut() {
            // 检查进程是否还活着
            match child.try_wait() {
                Ok(Some(status)) => {
                    // 进程已退出
                    let pid = child.id();
                    let exit_info = if let Some(code) = status.code() {
                        format!("退出码: {}", code)
                    } else {
                        "被信号终止".to_string()
                    };
                    log::warn!("Clash 进程已退出 (PID: {}, {})", pid, exit_info);

                    *child_guard = None;
                    *self.start_time.lock().unwrap_or_else(|e| {
                        log::warn!("StartTime 锁中毒，正在恢复");
                        e.into_inner()
                    }) = None;
                    false
                }
                Ok(None) => {
                    // 进程还在运行
                    true
                }
                Err(e) => {
                    // 出错，假定已停止
                    let pid = child.id();
                    log::error!("检查 Clash 进程状态失败 (PID: {}): {}", pid, e);

                    *child_guard = None;
                    *self.start_time.lock().unwrap_or_else(|e| {
                        log::warn!("StartTime 锁中毒，正在恢复");
                        e.into_inner()
                    }) = None;
                    false
                }
            }
        } else {
            false
        }
    }

    // 获取 Clash 状态（不需要可变引用，支持并发读）
    pub fn get_status(&self) -> ClashStatus {
        let running = self.is_running();

        let pid = if running {
            self.child
                .lock()
                .unwrap_or_else(|e| {
                    log::warn!("Child 锁中毒，正在恢复");
                    e.into_inner()
                })
                .as_ref()
                .map(|c| c.id())
        } else {
            None
        };

        let uptime = if running {
            self.start_time
                .lock()
                .unwrap_or_else(|e| {
                    log::warn!("StartTime 锁中毒，正在恢复");
                    e.into_inner()
                })
                .map(|t| t.elapsed().as_secs())
                .unwrap_or(0)
        } else {
            0
        };

        ClashStatus {
            is_running: running,
            pid,
            uptime,
        }
    }

    // 格式化 IO 错误提示
    fn format_io_error_hint(e: &std::io::Error) -> String {
        use std::io::ErrorKind;

        match e.kind() {
            ErrorKind::NotFound => {
                "可能原因：\n1. 核心文件路径错误\n2. 核心文件不存在\n3. 缺少执行权限\n提示: 请检查核心文件是否存在且可执行".to_string()
            }
            ErrorKind::PermissionDenied => {
                "可能原因：\n1. 缺少执行权限\n2. 被防火墙阻止\n3. 端口被占用\n提示: 请检查文件权限和防火墙设置".to_string()
            }
            ErrorKind::AddrInUse => {
                "可能原因：\n1. 端口已被占用\n2. Clash 已在运行\n提示: 请检查端口是否被占用或尝试更换端口".to_string()
            }
            _ => {
                #[cfg(windows)]
                {
                    if let Some(code) = e.raw_os_error() {
                        format!("Windows 错误代码: 0x{:X}\n提示: 请检查系统日志获取更多信息", code)
                    } else {
                        "提示: 请检查系统日志获取更多信息".to_string()
                    }
                }
                #[cfg(not(windows))]
                {
                    "提示: 请检查系统日志获取更多信息".to_string()
                }
            }
        }
    }
}

impl Drop for ClashManager {
    fn drop(&mut self) {
        // 确保进程被清理
        if let Err(e) = self.stop() {
            log::error!("清理 Clash 进程失败: {}", e);
        }
    }
}

// 扩展 JoinHandle 以支持超时
trait JoinHandleExt<T> {
    fn join_timeout(
        self,
        duration: std::time::Duration,
    ) -> Result<Result<T, Box<dyn std::any::Any + Send>>, ()>;
}

impl<T> JoinHandleExt<T> for std::thread::JoinHandle<T> {
    fn join_timeout(
        self,
        duration: std::time::Duration,
    ) -> Result<Result<T, Box<dyn std::any::Any + Send>>, ()> {
        let start = std::time::Instant::now();

        loop {
            if self.is_finished() {
                return Ok(self.join());
            }

            if start.elapsed() >= duration {
                return Err(());
            }

            std::thread::sleep(std::time::Duration::from_millis(100));
        }
    }
}
