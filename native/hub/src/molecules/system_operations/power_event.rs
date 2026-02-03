// Windows 电源事件监听：监听休眠与唤醒事件并上报到 Flutter

#[cfg(target_os = "windows")]
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
#[cfg(target_os = "windows")]
use windows::Win32::Foundation::{
    GetLastError, HANDLE, HWND, LPARAM, LRESULT, WIN32_ERROR, WPARAM,
};
#[cfg(target_os = "windows")]
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
#[cfg(target_os = "windows")]
use windows::Win32::System::Power::{
    POWERBROADCAST_SETTING, RegisterPowerSettingNotification, UnregisterPowerSettingNotification,
};
#[cfg(target_os = "windows")]
use windows::Win32::System::Threading::GetCurrentThreadId;
#[cfg(target_os = "windows")]
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW, GetMessageW,
    PostThreadMessageW, REGISTER_NOTIFICATION_FLAGS, RegisterClassW, TranslateMessage,
    WINDOW_EX_STYLE, WM_POWERBROADCAST, WM_QUIT, WNDCLASSW, WS_OVERLAPPEDWINDOW,
};
#[cfg(target_os = "windows")]
use windows::core::GUID;

use rinf::{RustSignal, SignalPiece};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, SignalPiece)]
pub enum PowerEventType {
    Suspend,
    ResumeAutomatic,
    ResumeSuspend,
}

#[derive(Serialize, RustSignal)]
pub struct SystemPowerEvent {
    pub event_type: PowerEventType,
}

// GUID_MONITOR_POWER_ON: 监视器电源状态
#[cfg(target_os = "windows")]
#[allow(dead_code)]
const GUID_MONITOR_POWER_ON: GUID = GUID {
    data1: 0x02731015,
    data2: 0x4510,
    data3: 0x4526,
    data4: [0x99, 0xE6, 0xE5, 0xA1, 0x7E, 0xBD, 0x1A, 0xEA],
};

// GUID_CONSOLE_DISPLAY_STATE: 控制台显示状态
#[cfg(target_os = "windows")]
const GUID_CONSOLE_DISPLAY_STATE: GUID = GUID {
    data1: 0x6FE69556,
    data2: 0x704A,
    data3: 0x47A0,
    data4: [0x8F, 0x24, 0xC2, 0x8D, 0x93, 0x6F, 0xDA, 0x47],
};

#[cfg(target_os = "windows")]
const ERROR_CLASS_ALREADY_EXISTS_CODE: u32 = 1410;

#[cfg(target_os = "windows")]
const PBT_APMSUSPEND: u32 = 0x0004;
#[cfg(target_os = "windows")]
const PBT_APMRESUMEAUTOMATIC: u32 = 0x0012;
#[cfg(target_os = "windows")]
const PBT_APMRESUMESUSPEND: u32 = 0x0007;
#[cfg(target_os = "windows")]
const PBT_POWERSETTINGCHANGE: u32 = 0x8013;

#[cfg(target_os = "windows")]
static RUNNING: AtomicBool = AtomicBool::new(false);

#[cfg(target_os = "windows")]
static LISTENER_THREAD_ID: AtomicU32 = AtomicU32::new(0);

#[cfg(target_os = "windows")]
unsafe extern "system" fn window_proc(
    hwnd: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    match msg {
        WM_POWERBROADCAST => {
            let event_type = wparam.0 as u32;

            match event_type {
                PBT_APMSUSPEND => {
                    log::info!("系统进入休眠");
                    SystemPowerEvent {
                        event_type: PowerEventType::Suspend,
                    }
                    .send_signal_to_dart();
                }

                PBT_APMRESUMEAUTOMATIC => {
                    log::info!("系统自动唤醒");
                    SystemPowerEvent {
                        event_type: PowerEventType::ResumeAutomatic,
                    }
                    .send_signal_to_dart();
                }

                PBT_APMRESUMESUSPEND => {
                    log::info!("用户唤醒系统");
                    SystemPowerEvent {
                        event_type: PowerEventType::ResumeSuspend,
                    }
                    .send_signal_to_dart();
                }

                PBT_POWERSETTINGCHANGE => {
                    let setting = lparam.0 as *const POWERBROADCAST_SETTING;
                    if setting.is_null() {
                        return LRESULT(0);
                    }

                    let setting_ref = unsafe { &*setting };
                    if setting_ref.PowerSetting == GUID_CONSOLE_DISPLAY_STATE {
                        let data_len = setting_ref.DataLength as usize;
                        if data_len >= 4 {
                            let bytes =
                                unsafe { std::slice::from_raw_parts(setting_ref.Data.as_ptr(), 4) };
                            let display_state =
                                u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);

                            match display_state {
                                0 => log::debug!("显示器关闭"),
                                1 => log::debug!("显示器开启"),
                                2 => log::debug!("显示器变暗"),
                                _ => log::debug!("显示器状态未知: {}", display_state),
                            }
                        } else {
                            log::debug!("显示器状态数据长度不足: {}", data_len);
                        }
                    }
                }

                _ => {
                    log::debug!("其他电源事件: 0x{:04X}", event_type);
                }
            }

            LRESULT(0)
        }
        _ => unsafe { DefWindowProcW(hwnd, msg, wparam, lparam) },
    }
}

#[cfg(target_os = "windows")]
pub fn start_power_event_listener() {
    if RUNNING.swap(true, Ordering::SeqCst) {
        log::warn!("电源监听器已运行");
        return;
    }

    log::info!("启动电源监听器");

    std::thread::spawn(|| {
        if let Err(e) = run_event_loop() {
            log::error!("电源事件循环失败: {}", e);
            RUNNING.store(false, Ordering::SeqCst);
            LISTENER_THREAD_ID.store(0, Ordering::SeqCst);
        }
    });
}

#[cfg(target_os = "windows")]
fn run_event_loop() -> Result<(), String> {
    unsafe {
        LISTENER_THREAD_ID.store(GetCurrentThreadId(), Ordering::SeqCst);

        let instance = GetModuleHandleW(None).map_err(|e| format!("获取模块句柄失败: {}", e))?;

        let class_name = windows::core::w!("StellibertyPowerEventClass");

        let wc = WNDCLASSW {
            lpfnWndProc: Some(window_proc),
            hInstance: instance.into(),
            lpszClassName: class_name,
            ..Default::default()
        };

        let atom = RegisterClassW(&wc);
        if atom == 0 {
            let last_error = GetLastError();
            if last_error != WIN32_ERROR(ERROR_CLASS_ALREADY_EXISTS_CODE) {
                return Err(format!("注册窗口类失败: {}", last_error.0));
            }
        }

        let hwnd = CreateWindowExW(
            WINDOW_EX_STYLE::default(),
            class_name,
            windows::core::w!("Stelliberty Power Event Window"),
            WS_OVERLAPPEDWINDOW,
            0,
            0,
            0,
            0,
            None,
            None,
            Some(instance.into()),
            None,
        )
        .map_err(|e| format!("创建窗口失败: {}", e))?;

        let notify_handle = RegisterPowerSettingNotification(
            HANDLE(hwnd.0),
            &GUID_CONSOLE_DISPLAY_STATE,
            REGISTER_NOTIFICATION_FLAGS(0x00000000),
        )
        .map_err(|e| format!("注册电源通知失败: {}", e))?;

        log::info!("电源监听器就绪");

        let mut msg = windows::Win32::UI::WindowsAndMessaging::MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).as_bool() {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        log::info!("清理电源监听器");

        if let Err(e) = UnregisterPowerSettingNotification(notify_handle) {
            log::warn!("注销电源通知失败: {}", e);
        }

        let _ = DestroyWindow(hwnd);

        RUNNING.store(false, Ordering::SeqCst);
        LISTENER_THREAD_ID.store(0, Ordering::SeqCst);

        Ok(())
    }
}

#[cfg(target_os = "windows")]
#[allow(dead_code)]
pub fn stop_power_event_listener() {
    if !RUNNING.load(Ordering::SeqCst) {
        return;
    }

    let thread_id = LISTENER_THREAD_ID.load(Ordering::SeqCst);
    if thread_id == 0 {
        log::warn!("电源监听器线程未就绪，无法停止");
        return;
    }

    log::info!("停止电源监听器");

    unsafe {
        if let Err(e) = PostThreadMessageW(thread_id, WM_QUIT, WPARAM(0), LPARAM(0)) {
            log::warn!("发送退出消息失败: {}", e);
            return;
        }
    }

    RUNNING.store(false, Ordering::SeqCst);
}

#[cfg(not(target_os = "windows"))]
pub fn start_power_event_listener() {}

#[cfg(not(target_os = "windows"))]
pub fn stop_power_event_listener() {}
