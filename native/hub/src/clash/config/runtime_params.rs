// Clash 运行时配置参数
//
// 定义所有需要在运行时注入到 Clash 配置中的参数

use rinf::{DartSignal, SignalPiece};
use serde::{Deserialize, Serialize};

// Clash 运行时配置参数
#[derive(Debug, Clone, Serialize, Deserialize, DartSignal, SignalPiece)]
pub struct RuntimeConfigParams {
    // 端口配置
    pub http_port: i32,

    // 全局配置
    pub is_ipv6_enabled: bool,
    pub is_allow_lan_enabled: bool,
    pub is_tcp_concurrent_enabled: bool,
    pub is_unified_delay_enabled: bool,
    pub outbound_mode: String, // "rule" | "global" | "direct"

    // TUN 配置
    pub is_tun_enabled: bool,
    pub tun_stack: String,
    pub tun_device: String,
    pub is_tun_auto_route_enabled: bool,
    pub is_tun_auto_redirect_enabled: bool,
    pub is_tun_auto_detect_interface_enabled: bool,
    pub tun_dns_hijack: Vec<String>,
    pub is_tun_strict_route_enabled: bool,
    pub tun_route_exclude_address: Vec<String>,
    pub is_tun_icmp_forwarding_disabled: bool,
    pub tun_mtu: i32,

    // 核心配置
    pub geodata_loader: String,
    pub find_process_mode: String,
    pub clash_core_log_level: String,
    pub external_controller: Option<String>,
    pub external_controller_secret: Option<String>,

    // Keep-Alive 配置
    pub is_keep_alive_enabled: bool,
    pub keep_alive_interval: Option<i32>,
}
