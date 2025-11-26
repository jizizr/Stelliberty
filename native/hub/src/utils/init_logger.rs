// 日志系统初始化
//
// 目的：配置统一的日志格式，与 Flutter 日志风格保持一致
// 支持文件日志输出到 running.logs（与 Dart 前端共享）

use chrono::Local;
use env_logger;
use log;
use once_cell::sync::Lazy;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;

// 日志文件大小限制（10MB）
const MAX_LOG_FILE_SIZE: u64 = 10 * 1024 * 1024;

// 全局日志文件路径
static LOG_FILE_PATH: Lazy<Mutex<Option<PathBuf>>> = Lazy::new(|| Mutex::new(None));

// 全局日志配置单例
static LOGGER: Lazy<()> = Lazy::new(|| {
    // 获取日志文件路径并设置
    if let Ok(app_data) = get_app_data_dir() {
        let log_path = app_data.join("running.logs");
        if let Ok(mut path_guard) = LOG_FILE_PATH.lock() {
            *path_guard = Some(log_path.clone());
            eprintln!("[RustLog] 应用日志文件路径: {}", log_path.display());
        }
    } else {
        eprintln!("[RustLog] 无法获取应用数据目录，应用日志将被禁用");
    }

    // Release 模式下完全禁用控制台日志输出
    // Debug 模式下：
    // - 项目代码使用 debug 级别
    // - 第三方库（tungstenite、reqwest 等）使用 warn 级别（过滤掉它们的 debug 日志）
    let default_level = if cfg!(debug_assertions) {
        "debug,tungstenite=warn,tokio_tungstenite=warn,reqwest=warn,hyper=warn,h2=warn"
    } else {
        "off" // Release 模式下禁用控制台日志
    };
    let env = env_logger::Env::default().default_filter_or(default_level);

    env_logger::Builder::from_env(env)
        .format(|buf, record| {
            // 获取当前时间戳（YYYY/MM/DD HH:mm:ss 格式）
            let timestamp = Local::now().format("%Y/%m/%d %H:%M:%S");

            let file = record.file().unwrap_or("unknown");
            let path_with_dots = file.replace(['/', '\\'], ".");

            const GREEN: &str = "\x1B[32m";
            const YELLOW: &str = "\x1B[33m";
            const RED: &str = "\x1B[31m";
            const CYAN: &str = "\x1B[36m";
            const RESET: &str = "\x1B[0m";

            let (level_str, color) = match record.level() {
                log::Level::Error => ("RustError", RED),
                log::Level::Warn => ("RustWarn", YELLOW),
                log::Level::Info => ("RustInfo", GREEN),
                log::Level::Debug => ("RustDebug", CYAN),
                log::Level::Trace => ("RustTrace", CYAN),
            };

            // 格式化日志：根据编译模式区分
            if cfg!(debug_assertions) {
                // 调试模式：控制台包含文件路径
                writeln!(
                    buf,
                    "{}[{}]{} {} {} >> {}",
                    color,
                    level_str,
                    RESET,
                    timestamp,
                    path_with_dots,
                    record.args()
                )?;
            } else {
                // 发布模式：控制台不输出（上面已设置 off）
                // 但这里依然格式化，以防有其他用途
                writeln!(
                    buf,
                    "{}[{}]{} {} >> {}",
                    color,
                    level_str,
                    RESET,
                    timestamp,
                    record.args()
                )?;
            }

            // 写入文件（无论 debug 还是 release 都写入）
            let file_log = if cfg!(debug_assertions) {
                // 调试模式：包含文件路径
                format!(
                    "[{}] {} {} >> {}",
                    level_str,
                    timestamp,
                    path_with_dots,
                    record.args()
                )
            } else {
                // 发布模式：移除文件路径
                format!("[{}] {} >> {}", level_str, timestamp, record.args())
            };

            // 写入文件（静默失败，不影响日志记录）
            let _ = write_to_file(&file_log);

            Ok(())
        })
        .init();
});

// 写入日志到文件
fn write_to_file(log_line: &str) -> std::io::Result<()> {
    let path_guard = match LOG_FILE_PATH.lock() {
        Ok(guard) => guard,
        Err(_) => return Ok(()), // 锁失败，静默返回
    };

    if let Some(ref path) = *path_guard {
        // 检查文件大小，超过限制时轮转
        check_and_rotate_log(path)?;

        // 追加写入日志（操作系统保证多进程追加的原子性）
        let mut file = OpenOptions::new()
            .create(true)
            .append(true) // 关键：追加模式
            .open(path)?;

        writeln!(file, "{}", log_line)?;
        file.flush()?; // 立即刷新到磁盘
    }

    Ok(())
}

// 检查并轮转日志文件
fn check_and_rotate_log(path: &PathBuf) -> std::io::Result<()> {
    // 检查文件是否存在且超过大小限制
    if let Ok(metadata) = fs::metadata(path)
        && metadata.len() > MAX_LOG_FILE_SIZE
    {
        // 重命名旧文件（避免与 Dart 冲突）
        let backup_path = path.with_extension("logs.old");

        // 如果旧备份存在，先删除
        let _ = fs::remove_file(&backup_path);

        // 重命名当前文件为备份（原子操作）
        // 如果失败（Dart 正在写入），静默忽略，下次再试
        let _ = fs::rename(path, &backup_path);

        // 写入新文件的首行提示
        let mut file = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(path)?;

        let clear_msg = format!(
            "[RustInfo] {} >> 应用日志文件已达到 {:.2} MB，已轮转到 running.logs.old\n",
            Local::now().format("%Y/%m/%d %H:%M:%S"),
            metadata.len() as f64 / 1024.0 / 1024.0
        );
        file.write_all(clear_msg.as_bytes())?;
        file.flush()?;
    }

    Ok(())
}

// 获取应用数据目录（与 Dart PathService 保持一致）
fn get_app_data_dir() -> Result<PathBuf, String> {
    // 桌面平台：使用可执行文件同级的 data 目录（便携模式）
    // 这与 Dart 的 PathService._determineAppDataPath() 逻辑一致
    use std::env;

    let binary_path = env::current_exe().map_err(|e| format!("无法获取可执行文件路径：{}", e))?;

    let binary_dir = binary_path
        .parent()
        .ok_or_else(|| "无法获取可执行文件目录".to_string())?;

    Ok(binary_dir.join("data"))
}

// 初始化日志系统
//
// 目的：配置环境日志记录器，支持多次调用而不会 panic
pub fn setup_logger() {
    Lazy::force(&LOGGER);
}
