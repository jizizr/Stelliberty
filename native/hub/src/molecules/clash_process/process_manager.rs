// Clash 进程管理：负责启动、停止与状态维护。
// 适用于非服务模式的直接进程控制。

use once_cell::sync::Lazy;
use rinf::{DartSignal, RustSignal};
use serde::{Deserialize, Serialize};
use std::sync::Mutex;

// Dart → Rust：启动 Clash 进程
#[derive(Deserialize, DartSignal)]
pub struct StartClashProcess {
    pub executable_path: String,
    pub args: Vec<String>,
}

// Dart → Rust：停止 Clash 进程
#[derive(Deserialize, DartSignal)]
pub struct StopClashProcess;

// Rust → Dart：Clash 进程操作结果
#[derive(Serialize, RustSignal)]
pub struct ClashProcessResult {
    pub is_successful: bool,
    pub error_message: Option<String>,
    pub pid: Option<u32>,
}

// 全局进程管理器
static PROCESS_MANAGER: Lazy<Mutex<Option<ClashProcess>>> = Lazy::new(|| Mutex::new(None));

// Clash 进程封装
struct ClashProcess {
    #[cfg(unix)]
    child: std::process::Child,
    #[cfg(windows)]
    process_handle: windows::Win32::Foundation::HANDLE,
    #[cfg(windows)]
    job_handle: windows::Win32::Foundation::HANDLE,
    #[cfg(windows)]
    pid: u32,
}

#[cfg(windows)]
unsafe impl Send for ClashProcess {}

impl ClashProcess {
    // 启动新的 Clash 进程
    fn start(executable_path: String, args: Vec<String>) -> Result<Self, String> {
        log::info!("启动 Clash 进程：{}", executable_path);
        log::info!("参数：{:?}", args);

        #[cfg(unix)]
        {
            use std::process::{Command, Stdio};

            let child = Command::new(&executable_path)
                .args(&args)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                .map_err(|e| format!("启动进程失败：{}", e))?;

            Ok(ClashProcess { child })
        }

        #[cfg(windows)]
        {
            use std::ffi::OsStr;
            use std::os::windows::ffi::OsStrExt;
            use windows::Win32::Foundation::CloseHandle;
            use windows::Win32::System::JobObjects::{
                AssignProcessToJobObject, CreateJobObjectW, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
                JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JobObjectExtendedLimitInformation,
                SetInformationJobObject,
            };
            use windows::Win32::System::Threading::{
                CREATE_NO_WINDOW, CREATE_SUSPENDED, CreateProcessW, PROCESS_INFORMATION,
                ResumeThread, STARTF_USESHOWWINDOW, STARTUPINFOW, TerminateProcess,
            };
            use windows::Win32::UI::WindowsAndMessaging::SW_HIDE;
            use windows::core::{PCWSTR, PWSTR};

            unsafe {
                // 构建命令行
                let mut command_line = format!("\"{}\"", executable_path);
                for arg in &args {
                    command_line.push(' ');
                    if arg.contains(' ') {
                        command_line.push_str(&format!("\"{}\"", arg));
                    } else {
                        command_line.push_str(arg);
                    }
                }

                let mut command_line_wide: Vec<u16> = OsStr::new(&command_line)
                    .encode_wide()
                    .chain(std::iter::once(0))
                    .collect();
                let command_line_ptr = PWSTR(command_line_wide.as_mut_ptr());

                // 创建 Job Object（确保子进程跟随父进程终止）
                let job_handle = CreateJobObjectW(None, PCWSTR::null())
                    .map_err(|_| "创建 Job Object 失败".to_string())?;

                let mut job_info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std::mem::zeroed();
                job_info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

                if SetInformationJobObject(
                    job_handle,
                    JobObjectExtendedLimitInformation,
                    &job_info as *const _ as *const _,
                    std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
                )
                .is_err()
                {
                    let _ = CloseHandle(job_handle);
                    return Err("设置 Job Object 信息失败".to_string());
                }

                // 配置启动信息（隐藏窗口）
                let mut startup_info: STARTUPINFOW = std::mem::zeroed();
                startup_info.cb = std::mem::size_of::<STARTUPINFOW>() as u32;
                startup_info.dwFlags = STARTF_USESHOWWINDOW;
                startup_info.wShowWindow = SW_HIDE.0 as u16;

                let mut process_info: PROCESS_INFORMATION = std::mem::zeroed();

                // 创建进程（挂起状态）
                if CreateProcessW(
                    PCWSTR::null(),
                    Some(command_line_ptr),
                    None,
                    None,
                    false,
                    CREATE_NO_WINDOW | CREATE_SUSPENDED,
                    None,
                    PCWSTR::null(),
                    &startup_info,
                    &mut process_info,
                )
                .is_err()
                {
                    let _ = CloseHandle(job_handle);
                    return Err("创建进程失败".to_string());
                }

                // 将进程分配到 Job Object
                if AssignProcessToJobObject(job_handle, process_info.hProcess).is_err() {
                    let _ = TerminateProcess(process_info.hProcess, 1);
                    let _ = CloseHandle(process_info.hProcess);
                    let _ = CloseHandle(process_info.hThread);
                    let _ = CloseHandle(job_handle);
                    return Err("分配进程到 Job Object 失败".to_string());
                }

                // 恢复进程运行
                if ResumeThread(process_info.hThread) == u32::MAX {
                    let _ = TerminateProcess(process_info.hProcess, 1);
                    let _ = CloseHandle(process_info.hProcess);
                    let _ = CloseHandle(process_info.hThread);
                    let _ = CloseHandle(job_handle);
                    return Err("恢复进程线程失败".to_string());
                }

                let pid = process_info.dwProcessId;
                let _ = CloseHandle(process_info.hThread);

                Ok(ClashProcess {
                    process_handle: process_info.hProcess,
                    job_handle,
                    pid,
                })
            }
        }
    }

    // 获取进程 PID
    fn pid(&self) -> u32 {
        #[cfg(unix)]
        {
            self.child.id()
        }
        #[cfg(windows)]
        {
            self.pid
        }
    }

    // 停止进程 - Unix 实现
    #[cfg(unix)]
    fn stop(mut self) -> Result<(), String> {
        let pid = self.pid();
        log::info!("正在停止 Clash 进程，PID：{}", pid);

        use nix::sys::signal::{Signal, kill};
        use nix::unistd::Pid;

        // 发送 SIGTERM 信号
        let nix_pid = Pid::from_raw(pid as i32);
        if let Err(e) = kill(nix_pid, Signal::SIGTERM) {
            log::error!("发送 SIGTERM 失败：{}", e);
        }

        // 等待进程退出
        match self.child.wait() {
            Ok(status) => {
                log::info!("进程已退出，状态：{:?}", status);
                Ok(())
            }
            Err(e) => {
                log::error!("等待进程退出失败：{}", e);
                Err(format!("等待进程退出失败：{}", e))
            }
        }
    }

    // 停止进程 - Windows 实现
    #[cfg(windows)]
    fn stop(self) -> Result<(), String> {
        let pid = self.pid();
        log::info!("正在停止 Clash 进程，PID：{}", pid);

        use std::time::Duration;
        use windows::Win32::Foundation::{CloseHandle, WAIT_OBJECT_0};
        use windows::Win32::System::Threading::WaitForSingleObject;

        unsafe {
            // 关闭 Job Object 触发子进程自动终止
            let _ = CloseHandle(self.job_handle);

            // 等待进程退出（最多 5 秒）
            let timeout_ms = Duration::from_secs(5).as_millis() as u32;
            let wait_result = WaitForSingleObject(self.process_handle, timeout_ms);

            match wait_result {
                WAIT_OBJECT_0 => {
                    log::info!("进程已安全退出");
                    let _ = CloseHandle(self.process_handle);
                    Ok(())
                }
                _ => {
                    log::warn!("进程在 5 秒后仍未退出");
                    let _ = CloseHandle(self.process_handle);
                    Ok(())
                }
            }
        }
    }
}

// 处理启动 Clash 进程的请求
impl StartClashProcess {
    pub fn handle(&self) {
        log::info!("收到启动 Clash 进程请求");

        let mut manager = PROCESS_MANAGER.lock().unwrap_or_else(|e| {
            log::error!("获取进程管理器锁失败：{}", e);
            e.into_inner()
        });

        // 检查是否已有进程在运行
        if manager.is_some() {
            log::warn!("Clash 进程已在运行");
            ClashProcessResult {
                is_successful: false,
                error_message: Some("进程已在运行".to_string()),
                pid: None,
            }
            .send_signal_to_dart();
            return;
        }

        // 启动新进程
        match ClashProcess::start(self.executable_path.clone(), self.args.clone()) {
            Ok(process) => {
                let pid = process.pid();
                *manager = Some(process);

                log::info!("Clash 进程启动成功，PID：{}", pid);
                ClashProcessResult {
                    is_successful: true,
                    error_message: None,
                    pid: Some(pid),
                }
                .send_signal_to_dart();
            }
            Err(e) => {
                log::error!("启动 Clash 进程失败：{}", e);
                ClashProcessResult {
                    is_successful: false,
                    error_message: Some(e),
                    pid: None,
                }
                .send_signal_to_dart();
            }
        }
    }
}

// 处理停止 Clash 进程的请求
impl StopClashProcess {
    pub fn handle(&self) {
        log::info!("收到停止 Clash 进程请求");

        let mut manager = PROCESS_MANAGER.lock().unwrap_or_else(|e| {
            log::error!("获取进程管理器锁失败：{}", e);
            e.into_inner()
        });

        match manager.take() {
            Some(process) => match process.stop() {
                Ok(()) => {
                    log::info!("Clash 进程已停止");

                    ClashProcessResult {
                        is_successful: true,
                        error_message: None,
                        pid: None,
                    }
                    .send_signal_to_dart();
                }
                Err(e) => {
                    log::error!("停止 Clash 进程失败：{}", e);
                    ClashProcessResult {
                        is_successful: false,
                        error_message: Some(e),
                        pid: None,
                    }
                    .send_signal_to_dart();
                }
            },
            None => {
                log::warn!("没有运行中的 Clash 进程");
                ClashProcessResult {
                    is_successful: true,
                    error_message: None,
                    pid: None,
                }
                .send_signal_to_dart();
            }
        }
    }
}

// 清理资源（应用退出时调用）
pub fn cleanup() {
    log::info!("清理 Clash 进程管理器…");

    let mut manager = PROCESS_MANAGER.lock().unwrap_or_else(|e| {
        log::error!("获取进程管理器锁失败：{}", e);
        e.into_inner()
    });

    if let Some(process) = manager.take() {
        log::info!("发现运行中的 Clash 进程，正在清理…");
        if let Err(e) = process.stop() {
            log::error!("清理 Clash 进程失败：{}", e);
        }
    }
}

// 清理进程管理器状态（服务卸载时调用）
pub async fn cleanup_process_manager() {
    log::info!("清理进程管理器状态（服务卸载）");

    let mut manager = PROCESS_MANAGER.lock().unwrap_or_else(|e| {
        log::error!("获取进程管理器锁失败：{}", e);
        e.into_inner()
    });

    if manager.take().is_some() {
        log::info!("进程管理器已清空");
    }
}

pub fn init() {
    use tokio::spawn;

    // 启动 Clash 进程
    spawn(async {
        let receiver = StartClashProcess::get_dart_signal_receiver();
        while let Some(dart_signal) = receiver.recv().await {
            let message = dart_signal.message;
            if let Err(e) = tokio::task::spawn_blocking(move || {
                message.handle();
            })
            .await
            {
                log::error!("启动进程的任务执行失败（可能线程池耗尽）：{}", e);
                ClashProcessResult {
                    is_successful: false,
                    error_message: Some(format!("任务执行失败：{}", e)),
                    pid: None,
                }
                .send_signal_to_dart();
            }
        }
    });

    // 停止 Clash 进程
    spawn(async {
        let receiver = StopClashProcess::get_dart_signal_receiver();
        while let Some(dart_signal) = receiver.recv().await {
            let message = dart_signal.message;
            if let Err(e) = tokio::task::spawn_blocking(move || {
                message.handle();
            })
            .await
            {
                log::error!("停止进程的任务执行失败（可能线程池耗尽）：{}", e);
                ClashProcessResult {
                    is_successful: false,
                    error_message: Some(format!("任务执行失败：{}", e)),
                    pid: None,
                }
                .send_signal_to_dart();
            }
        }
    });
}
