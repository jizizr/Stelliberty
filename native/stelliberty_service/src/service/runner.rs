// 统一的服务运行逻辑（Windows Service / Linux systemd）

#[cfg(any(windows, target_os = "linux"))]
use crate::clash::ClashManager;
#[cfg(any(windows, target_os = "linux"))]
use crate::ipc::IpcServer;
#[cfg(any(windows, target_os = "linux"))]
use crate::service::handler;
#[cfg(target_os = "linux")]
use anyhow::Result;
#[cfg(any(windows, target_os = "linux"))]
use std::sync::Arc;
#[cfg(any(windows, target_os = "linux"))]
use tokio::sync::{RwLock, mpsc};

#[cfg(windows)]
const SERVICE_NAME: &str = "StellibertyService";

// ============ Windows Service 实现 ============

#[cfg(windows)]
use std::ffi::OsString;
#[cfg(windows)]
use std::time::{Duration, Instant};
#[cfg(windows)]
use windows_service::{
    define_windows_service,
    service::{
        ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus,
        ServiceType,
    },
    service_control_handler::{self, ServiceControlHandlerResult},
    service_dispatcher,
};

#[cfg(windows)]
const SERVICE_TYPE: ServiceType = ServiceType::OWN_PROCESS;

#[cfg(windows)]
pub fn run_as_service() -> Result<(), windows_service::Error> {
    service_dispatcher::start(SERVICE_NAME, ffi_service_main)
}

#[cfg(windows)]
define_windows_service!(ffi_service_main, service_main_windows);

#[cfg(windows)]
fn service_main_windows(_arguments: Vec<OsString>) {
    // 初始化日志系统
    crate::logger::init_logger();
    log::info!("Windows Service 主函数启动");

    if let Err(e) = run_service_windows() {
        log::error!("Service 运行失败: {e:?}");
    }
}

#[cfg(windows)]
fn run_service_windows() -> Result<(), Box<dyn std::error::Error>> {
    let (shutdown_tx, mut shutdown_rx) = mpsc::channel::<()>(1);

    let shutdown_tx_for_handler = shutdown_tx.clone();
    let event_handler = move |control_event| -> ServiceControlHandlerResult {
        match control_event {
            ServiceControl::Stop => {
                log::info!("收到停止信号");
                let _ = shutdown_tx_for_handler.blocking_send(());
                ServiceControlHandlerResult::NoError
            }
            ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
            _ => ServiceControlHandlerResult::NotImplemented,
        }
    };

    let status_handle = service_control_handler::register(SERVICE_NAME, event_handler)?;

    status_handle.set_service_status(ServiceStatus {
        service_type: SERVICE_TYPE,
        current_state: ServiceState::StartPending,
        controls_accepted: ServiceControlAccept::empty(),
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 0,
        wait_hint: Duration::from_secs(5),
        process_id: None,
    })?;

    log::info!("Stelliberty Service 启动中...");

    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;

    runtime.block_on(async move {
        let clash_manager = Arc::new(RwLock::new(ClashManager::new()));
        let last_heartbeat = Arc::new(RwLock::new(Instant::now()));
        let handler = handler::create_handler(clash_manager.clone(), last_heartbeat.clone());

        // 创建就绪信号通道
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
        let mut ipc_server = IpcServer::new_with_ready_signal(handler, ready_tx);

        let ipc_handle = tokio::spawn(async move {
            if let Err(e) = ipc_server.run().await {
                log::error!("IPC 服务器运行失败: {e}");
            }
        });

        // 等待 IPC 服务器就绪（Named Pipe 创建完成）
        if tokio::time::timeout(Duration::from_secs(5), ready_rx)
            .await
            .is_err()
        {
            log::error!("等待 IPC 服务器就绪超时");
        }

        if let Err(e) = status_handle.set_service_status(ServiceStatus {
            service_type: SERVICE_TYPE,
            current_state: ServiceState::Running,
            controls_accepted: ServiceControlAccept::STOP,
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: Duration::default(),
            process_id: None,
        }) {
            log::error!("设置服务状态为 Running 失败: {e:?}");
        }

        log::info!("Stelliberty Service 运行中");

        // 启动心跳监控器（HeartbeatMonitor）任务
        // 心跳超时只停止 Clash 核心，服务继续运行等待重连
        let heartbeat_clash_manager = clash_manager.clone();
        let heartbeat_last_heartbeat = last_heartbeat.clone();
        let heartbeat_handle = tokio::spawn(async move {
            const HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(70);
            const CHECK_INTERVAL: Duration = Duration::from_secs(30);

            log::info!("启动心跳监控器，超时时间: {}s", HEARTBEAT_TIMEOUT.as_secs());

            // 记录上一次检查的时间，用于检测系统休眠
            let mut last_check_time = Instant::now();

            loop {
                tokio::time::sleep(CHECK_INTERVAL).await;

                let now = Instant::now();
                let check_elapsed = now.duration_since(last_check_time);
                last_check_time = now;

                // 检测系统休眠唤醒：两次检查之间的间隔远大于 CHECK_INTERVAL
                // 正常情况下 check_elapsed 约等于 CHECK_INTERVAL（30s）
                // 如果 > 60s，说明系统可能刚从休眠中恢复
                if check_elapsed > Duration::from_secs(60) {
                    log::info!(
                        "检测到系统休眠唤醒（检查间隔: {}s），重置心跳计时器",
                        check_elapsed.as_secs()
                    );
                    *heartbeat_last_heartbeat.write().await = Instant::now();
                    continue;
                }

                let elapsed = heartbeat_last_heartbeat.read().await.elapsed();
                if elapsed > HEARTBEAT_TIMEOUT {
                    log::warn!(
                        "超过 {} 秒未收到主程序心跳，停止 Clash 核心（服务继续运行）",
                        HEARTBEAT_TIMEOUT.as_secs()
                    );

                    // 只停止 Clash 核心，不关闭服务
                    let mut manager = heartbeat_clash_manager.write().await;
                    if let Err(e) = manager.stop() {
                        log::error!("心跳超时停止 Clash 失败: {}", e);
                    } else {
                        log::info!("心跳超时，Clash 核心已停止，等待主程序重连");
                    }

                    // 重置心跳时间，避免反复触发
                    *heartbeat_last_heartbeat.write().await = Instant::now();
                } else {
                    log::debug!("心跳正常，距离上次心跳: {}s", elapsed.as_secs());
                }
            }
        });

        shutdown_rx.recv().await;
        log::info!("正在停止服务...");

        if let Err(e) = status_handle.set_service_status(ServiceStatus {
            service_type: SERVICE_TYPE,
            current_state: ServiceState::StopPending,
            controls_accepted: ServiceControlAccept::empty(),
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: Duration::from_secs(8),
            process_id: None,
        }) {
            log::error!("设置服务状态为 StopPending 失败: {e:?}");
        }

        // 添加超时保护：确保在 Windows 强制终止前完成 Clash 清理
        use tokio::time::timeout;

        match timeout(Duration::from_secs(5), async {
            let mut manager = clash_manager.write().await;
            manager.stop()
        })
        .await
        {
            Ok(Ok(())) => {
                log::info!("Clash 已正常停止");
            }
            Ok(Err(e)) => {
                log::error!("停止 Clash 失败: {}, 服务将继续退出", e);
            }
            Err(_) => {
                log::error!("停止 Clash 超时 (5 秒)，服务将强制退出");
                // 超时后尝试通过 drop 清理
                drop(clash_manager);
            }
        }

        heartbeat_handle.abort();
        ipc_handle.abort();
        log::info!("服务已停止");
    });

    status_handle.set_service_status(ServiceStatus {
        service_type: SERVICE_TYPE,
        current_state: ServiceState::Stopped,
        controls_accepted: ServiceControlAccept::empty(),
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 0,
        wait_hint: Duration::default(),
        process_id: None,
    })?;

    Ok(())
}

// ============ Linux systemd 实现 ============

#[cfg(target_os = "linux")]
use std::time::{Duration, Instant};

#[cfg(target_os = "linux")]
pub async fn run_service() -> Result<()> {
    // 初始化日志系统（与 Windows service_main_windows 保持一致）
    crate::logger::init_logger();
    log::info!("Stelliberty Service (Linux) 启动中...");

    let (shutdown_tx, mut shutdown_rx) = mpsc::channel::<()>(1);

    // 注册 Unix 信号处理器
    let shutdown_tx_clone = shutdown_tx.clone();
    tokio::spawn(async move {
        use tokio::signal::unix::{SignalKind, signal};

        let mut sigterm = match signal(SignalKind::terminate()) {
            Ok(s) => s,
            Err(e) => {
                log::error!("注册 SIGTERM 失败: {e}");
                let _ = shutdown_tx_clone.send(()).await;
                return;
            }
        };

        let mut sigint = match signal(SignalKind::interrupt()) {
            Ok(s) => s,
            Err(e) => {
                log::error!("注册 SIGINT 失败: {e}");
                let _ = shutdown_tx_clone.send(()).await;
                return;
            }
        };

        tokio::select! {
            _ = sigterm.recv() => log::info!("收到 SIGTERM 信号"),
            _ = sigint.recv() => log::info!("收到 SIGINT 信号"),
        }

        let _ = shutdown_tx_clone.send(()).await;
    });

    let clash_manager = Arc::new(RwLock::new(ClashManager::new()));
    let last_heartbeat = Arc::new(RwLock::new(Instant::now()));
    let handler = handler::create_handler(clash_manager.clone(), last_heartbeat.clone());

    // 创建就绪信号通道
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    let mut ipc_server = IpcServer::new_with_ready_signal(handler, ready_tx);

    let ipc_handle = tokio::spawn(async move {
        if let Err(e) = ipc_server.run().await {
            log::error!("IPC 服务器运行失败: {}", e);
        }
    });

    // 等待 IPC 服务器就绪（Unix Socket 创建完成）
    if tokio::time::timeout(Duration::from_secs(5), ready_rx)
        .await
        .is_err()
    {
        log::error!("等待 IPC 服务器就绪超时");
    }

    log::info!("Stelliberty Service 运行中");

    // 启动心跳监控器（HeartbeatMonitor）任务
    // 心跳超时只停止 Clash 核心，服务继续运行等待重连
    let heartbeat_clash_manager = clash_manager.clone();
    let heartbeat_last_heartbeat = last_heartbeat.clone();
    let heartbeat_handle = tokio::spawn(async move {
        const HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(70);
        const CHECK_INTERVAL: Duration = Duration::from_secs(30);

        log::info!("启动心跳监控器，超时时间: {}s", HEARTBEAT_TIMEOUT.as_secs());

        // 记录上一次检查的时间，用于检测系统休眠
        let mut last_check_time = Instant::now();

        loop {
            tokio::time::sleep(CHECK_INTERVAL).await;

            let now = Instant::now();
            let check_elapsed = now.duration_since(last_check_time);
            last_check_time = now;

            // 检测系统休眠唤醒：两次检查之间的间隔远大于 CHECK_INTERVAL
            // 正常情况下 check_elapsed 约等于 CHECK_INTERVAL（30s）
            // 如果 > 60s，说明系统可能刚从休眠中恢复
            if check_elapsed > Duration::from_secs(60) {
                log::info!(
                    "检测到系统休眠唤醒（检查间隔: {}s），重置心跳计时器",
                    check_elapsed.as_secs()
                );
                *heartbeat_last_heartbeat.write().await = Instant::now();
                continue;
            }

            let elapsed = heartbeat_last_heartbeat.read().await.elapsed();
            if elapsed > HEARTBEAT_TIMEOUT {
                log::warn!(
                    "超过 {} 秒未收到主程序心跳，停止 Clash 核心（服务继续运行）",
                    HEARTBEAT_TIMEOUT.as_secs()
                );

                // 只停止 Clash 核心，不关闭服务
                let mut manager = heartbeat_clash_manager.write().await;
                if let Err(e) = manager.stop() {
                    log::error!("心跳超时停止 Clash 失败: {}", e);
                } else {
                    log::info!("心跳超时，Clash 核心已停止，等待主程序重连");
                }

                // 重置心跳时间，避免反复触发
                *heartbeat_last_heartbeat.write().await = Instant::now();
            } else {
                log::debug!("心跳正常，距离上次心跳: {}s", elapsed.as_secs());
            }
        }
    });

    shutdown_rx.recv().await;
    log::info!("正在停止服务...");

    // 添加超时保护：确保 Clash 被正确清理
    use tokio::time::timeout;

    match timeout(Duration::from_secs(5), async {
        let mut manager = clash_manager.write().await;
        manager.stop()
    })
    .await
    {
        Ok(Ok(())) => {
            log::info!("Clash 已正常停止");
        }
        Ok(Err(e)) => {
            log::error!("停止 Clash 失败: {}, 服务将继续退出", e);
        }
        Err(_) => {
            log::error!("停止 Clash 超时 (5秒)，服务将强制退出");
            // 超时后尝试通过 drop 清理
            drop(clash_manager);
        }
    }

    heartbeat_handle.abort();
    ipc_handle.abort();
    log::info!("服务已停止");
    Ok(())
}
