// 日志模块
//
// 提供内存日志缓冲，支持通过 IPC 查看日志

use chrono::Local;
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use tokio::sync::broadcast;

// 日志广播通道容量
const LOG_BROADCAST_CAPACITY: usize = 100;

// 全局日志缓冲区，保存最近的1000行日志
static LOG_BUFFER: once_cell::sync::Lazy<Arc<Mutex<VecDeque<String>>>> =
    once_cell::sync::Lazy::new(|| Arc::new(Mutex::new(VecDeque::with_capacity(1000))));

// 全局日志广播通道（用于实时日志流）
static LOG_BROADCASTER: once_cell::sync::Lazy<broadcast::Sender<String>> =
    once_cell::sync::Lazy::new(|| {
        let (tx, _) = broadcast::channel(LOG_BROADCAST_CAPACITY);
        tx
    });

// 获取最近的 N 行日志
pub fn get_recent_logs(lines: usize) -> Vec<String> {
    let buffer = match LOG_BUFFER.lock() {
        Ok(guard) => guard,
        Err(poisoned) => {
            // Mutex 被污染时恢复数据
            log::warn!("日志缓冲区锁被污染，正在恢复");
            poisoned.into_inner()
        }
    };
    let start = if buffer.len() > lines {
        buffer.len() - lines
    } else {
        0
    };
    buffer.iter().skip(start).cloned().collect()
}

// 订阅日志流
pub fn subscribe_logs() -> broadcast::Receiver<String> {
    LOG_BROADCASTER.subscribe()
}

// 自定义日志记录器，将日志保存到内存缓冲区
struct MemoryLogger;

impl log::Log for MemoryLogger {
    fn enabled(&self, _metadata: &log::Metadata) -> bool {
        true
    }

    fn log(&self, record: &log::Record) {
        if self.enabled(record.metadata()) {
            let now = Local::now();
            let log_line = format!(
                "[{}] {} {} >> {}",
                record.level(),
                now.format("%H:%M:%S"),
                record.target(),
                record.args()
            );

            // 输出到 stderr（用于控制台模式）
            eprintln!("{}", log_line);

            // 保存到内存缓冲区
            let mut buffer = match LOG_BUFFER.lock() {
                Ok(guard) => guard,
                Err(poisoned) => {
                    // Mutex 被污染时恢复数据，避免日志系统导致程序崩溃
                    eprintln!("[WARN] 日志缓冲区锁被污染，正在恢复");
                    poisoned.into_inner()
                }
            };
            buffer.push_back(log_line.clone());

            // 保持缓冲区大小不超过 1000 行
            while buffer.len() > 1000 {
                buffer.pop_front();
            }

            // 广播日志到所有订阅者
            let _ = LOG_BROADCASTER.send(log_line);
        }
    }

    fn flush(&self) {}
}

// 初始化日志系统
pub fn init_logger() {
    static LOGGER: MemoryLogger = MemoryLogger;

    log::set_logger(&LOGGER)
        .map(|()| log::set_max_level(log::LevelFilter::Info))
        .expect("无法初始化日志系统");

    log::info!("日志系统初始化完成 (内存缓冲模式)");
}
