// Stelliberty Service Library
//
// 后台服务程序，负责以管理员权限运行 Clash 核心

pub mod clash;
pub mod ipc;
pub mod logger;
pub mod service;

use anyhow::Result;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{RwLock, mpsc};

// 命令行入口
pub fn cli() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();

    // 无参数时：尝试作为系统服务运行，如果不是服务模式则显示帮助
    if args.len() <= 1 {
        // Windows: 尝试作为 Windows Service 运行
        #[cfg(windows)]
        if service::run_as_service().is_ok() {
            return Ok(());
        }

        // Linux: 作为 systemd 服务运行（systemd 启动时不带参数）
        #[cfg(target_os = "linux")]
        {
            // 检查是否由 systemd 启动（INVOCATION_ID 环境变量）
            if std::env::var("INVOCATION_ID").is_ok() {
                // 由 systemd 启动，运行服务（日志初始化在 run_service 内部）
                let rt = tokio::runtime::Runtime::new()?;
                return rt.block_on(service::runner::run_service());
            }
        }

        // macOS: 作为 launchd 服务运行（launchd 启动时不带参数且无 TTY）
        #[cfg(target_os = "macos")]
        {
            use std::io::IsTerminal;
            // 检查是否由 launchd 启动（stdin 不是 TTY）
            if !std::io::stdin().is_terminal() {
                // 由 launchd 启动，运行服务
                logger::init_logger();
                let rt = tokio::runtime::Runtime::new()?;
                return rt.block_on(run_console_mode());
            }
        }

        // 不是服务模式（用户直接运行），显示帮助
        print_usage();
        return Ok(());
    }

    // 这些命令不需要管理员权限
    let no_admin_required = matches!(args[1].as_str(), "logs" | "version" | "-v" | "--version");

    // 需要权限的命令检查权限
    if !no_admin_required && !check_privileges() {
        print_privilege_error();
        std::process::exit(1);
    }

    handle_command(&args)?;
    Ok(())
}

// 检查是否有足够的权限运行
fn check_privileges() -> bool {
    #[cfg(windows)]
    {
        use windows::Win32::UI::Shell::IsUserAnAdmin;
        unsafe { IsUserAnAdmin().as_bool() }
    }

    #[cfg(not(windows))]
    {
        unsafe { libc::geteuid() == 0 }
    }
}

// 打印权限不足的错误信息
pub fn print_privilege_error() {
    eprintln!("错误: 此操作需要管理员权限");
    eprintln!();
    eprintln!("请以管理员身份运行此命令");
    #[cfg(windows)]
    eprintln!("提示: 右键点击终端，选择「以管理员身份运行」");
    #[cfg(not(windows))]
    eprintln!("提示: 使用 sudo 运行此命令");
}

// 打印使用说明
pub fn print_usage() {
    println!("Stelliberty Service v{}", env!("CARGO_PKG_VERSION"));
    println!();
    println!("可用命令：");
    println!("  install    - 安装并启动服务");
    println!("  uninstall  - 停止并卸载服务");
    println!("  start      - 启动服务");
    println!("  stop       - 停止服务");
    println!("  logs       - 实时监控服务日志");
    println!("  version    - 显示版本号");
    println!();
    #[cfg(windows)]
    println!("注意：install/uninstall/start/stop 需要管理员权限");
    #[cfg(not(windows))]
    println!("注意：install/uninstall/start/stop 需要 root 权限");
}

// 控制台模式运行（用于调试）
pub async fn run_console_mode() -> Result<()> {
    log::info!("以控制台模式运行服务");

    // 创建一个 channel 用于优雅关闭
    let (shutdown_tx, mut shutdown_rx) = mpsc::channel::<()>(1);

    // 注册 Ctrl+C 信号处理器
    let shutdown_tx_clone = shutdown_tx.clone();
    tokio::spawn(async move {
        if let Err(e) = tokio::signal::ctrl_c().await {
            log::error!("注册 Ctrl+C 处理器失败: {e}");
            let _ = shutdown_tx_clone.send(()).await;
            return;
        }
        log::info!("收到 Ctrl+C 信号");
        let _ = shutdown_tx_clone.send(()).await;
    });

    // 创建共享状态
    let clash_manager = Arc::new(RwLock::new(clash::ClashManager::new()));
    let last_heartbeat = Arc::new(RwLock::new(Instant::now()));

    // 创建 IPC 服务端和处理器
    let handler = service::handler::create_handler(clash_manager.clone(), last_heartbeat.clone());
    let mut ipc_server = ipc::IpcServer::new(handler);

    // 启动心跳监控器（HeartbeatMonitor）任务
    let monitor_shutdown_tx = shutdown_tx.clone();
    tokio::spawn(async move {
        const HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(70);
        const CHECK_INTERVAL: Duration = Duration::from_secs(30);

        log::info!("启动心跳监控器，超时时间: {}s", HEARTBEAT_TIMEOUT.as_secs());

        loop {
            tokio::time::sleep(CHECK_INTERVAL).await;
            let elapsed = last_heartbeat.read().await.elapsed();
            if elapsed > HEARTBEAT_TIMEOUT {
                log::warn!(
                    "超过 {} 秒未收到主程序心跳，判定为孤立进程，服务将自动关闭...",
                    HEARTBEAT_TIMEOUT.as_secs()
                );
                if monitor_shutdown_tx.send(()).await.is_err() {
                    log::error!("发送关闭信号失败，服务可能无法正常退出");
                }
                break;
            } else {
                log::debug!("心跳正常，距离上次心跳: {}s", elapsed.as_secs());
            }
        }
    });

    // 运行 IPC 服务端
    let ipc_handle = tokio::spawn(async move {
        if let Err(e) = ipc_server.run().await {
            log::error!("IPC 服务器运行失败: {e}");
        }
    });

    log::info!("服务运行中，按 Ctrl+C 退出");

    // 等待关闭信号
    shutdown_rx.recv().await;
    log::info!("正在停止服务...");

    // 添加超时保护
    use tokio::time::timeout;
    match timeout(Duration::from_secs(5), async {
        let mut manager = clash_manager.write().await;
        manager.stop()
    })
    .await
    {
        Ok(Ok(())) => log::info!("Clash 已正常停止"),
        Ok(Err(e)) => log::error!("停止 Clash 失败: {e}, 服务将继续退出"),
        Err(_) => {
            log::error!("停止 Clash 超时 (5 秒)，服务将强制退出");
            drop(clash_manager);
        }
    }

    ipc_handle.abort();
    log::info!("服务已停止");
    Ok(())
}

// 处理命令行参数
pub fn handle_command(args: &[String]) -> Result<Option<()>> {
    if args.len() <= 1 {
        // 无命令，显示帮助信息
        print_usage();
        return Ok(Some(()));
    }

    match args[1].as_str() {
        "install" => {
            service::install_service()?;
            Ok(Some(()))
        }
        "uninstall" => {
            service::uninstall_service()?;
            Ok(Some(()))
        }
        "start" => {
            service::start_service()?;
            Ok(Some(()))
        }
        "stop" => {
            service::stop_service()?;
            Ok(Some(()))
        }
        "logs" => {
            tokio::runtime::Runtime::new()?.block_on(async { follow_logs().await })?;
            Ok(Some(()))
        }
        "version" | "-v" | "--version" => {
            println!("Stelliberty Service v{}", env!("CARGO_PKG_VERSION"));
            Ok(Some(()))
        }
        _ => {
            eprintln!("未知命令: {}", args[1]);
            println!();
            print_usage();
            Ok(Some(()))
        }
    }
}

// 实时监控服务日志
async fn follow_logs() -> Result<()> {
    use ipc::IpcClient;
    use ipc::protocol::{IpcCommand, IpcResponse};

    let client = IpcClient::default();

    // 先获取历史日志（最近 500 条）
    match client
        .send_command(IpcCommand::GetLogs { lines: 500 })
        .await
    {
        Ok(IpcResponse::Logs { lines: log_lines }) => {
            for line in log_lines {
                println!("{}", line);
            }
        }
        Ok(_) => {}
        Err(_) => {
            println!("服务未运行，请先启动服务");
            return Ok(());
        }
    }

    // 接收实时日志流
    let _ = client
        .stream_logs(|line| {
            println!("{}", line);
            true
        })
        .await;

    println!("\n日志流已断开");
    Ok(())
}

// 服务主入口
pub async fn run() -> Result<()> {
    log::info!("Stelliberty Service v{} 启动", env!("CARGO_PKG_VERSION"));

    // Windows 平台作为 Windows Service 运行
    #[cfg(windows)]
    {
        if let Ok(()) = service::run_as_service() {
            return Ok(());
        }
        log::info!("非 Windows Service 模式，以控制台模式运行");
        run_console_mode().await
    }

    // Linux 平台作为 systemd service 运行
    #[cfg(target_os = "linux")]
    {
        service::run_service().await
    }

    // macOS 或其他平台以控制台模式运行
    #[cfg(not(any(windows, target_os = "linux")))]
    {
        run_console_mode().await
    }
}
