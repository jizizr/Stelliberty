// 应用更新服务：GitHub Release 检查

use reqwest;
use serde::{Deserialize, Serialize};
use std::cmp::Ordering;

// ============================================================================
// 数据结构
// ============================================================================

// GitHub Release API 响应
#[derive(Debug, Deserialize)]
struct GitHubRelease {
    tag_name: String,
    #[serde(rename = "html_url")]
    html_url: String,
    body: Option<String>,
    assets: Vec<GitHubAsset>,
}

#[derive(Debug, Deserialize)]
struct GitHubAsset {
    name: String,
    browser_download_url: String,
}

// 平台匹配规则
struct PlatformMatchRules {
    file_extension: &'static str,
    platform_keywords: &'static [&'static str],
    arch_keywords: &'static [&'static str],
    required_keywords: &'static [&'static str],
}

// ============================================================================
// 核心功能
// ============================================================================

// 检查 GitHub Release 更新
pub async fn check_github_update(
    current_version: &str,
    github_repo: &str,
) -> Result<UpdateCheckResult, String> {
    log::info!("开始检查 GitHub 更新: {}", github_repo);
    log::info!("当前版本: {}", current_version);

    // 构建 GitHub API URL
    let api_url = format!(
        "https://api.github.com/repos/{}/releases/latest",
        github_repo
    );

    // 发送 HTTP 请求
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .map_err(|e| format!("创建 HTTP 客户端失败: {}", e))?;

    let response = client
        .get(&api_url)
        .header("Accept", "application/vnd.github.v3+json")
        .header("User-Agent", "Stelliberty-App")
        .send()
        .await
        .map_err(|e| format!("HTTP 请求失败: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("GitHub API 返回错误: {}", response.status()));
    }

    // 解析 JSON 响应
    let release: GitHubRelease = response
        .json()
        .await
        .map_err(|e| format!("JSON 解析失败: {}", e))?;

    // 处理版本号
    let latest_version = release.tag_name.trim_start_matches('v');
    log::info!("最新版本: {}", latest_version);

    // 比较版本
    let has_update = compare_versions(current_version, latest_version) == Ordering::Less;

    // 检测当前平台和架构
    let platform = get_platform_name();
    let arch = get_architecture();
    log::info!("当前平台: {}, 架构: {}", platform, arch);

    // 查找匹配的安装包
    let download_url = find_matching_asset(&release.assets, &platform, &arch);

    if download_url.is_some() {
        log::info!("找到匹配的下载链接");
    } else {
        log::warn!("未找到匹配当前平台的安装包");
    }

    Ok(UpdateCheckResult {
        current_version: current_version.to_string(),
        latest_version: latest_version.to_string(),
        has_update,
        download_url,
        release_notes: release.body,
        html_url: Some(release.html_url),
    })
}

// 比较版本号
fn compare_versions(v1: &str, v2: &str) -> Ordering {
    let parts1: Vec<u32> = v1.split('.').filter_map(|s| s.parse().ok()).collect();
    let parts2: Vec<u32> = v2.split('.').filter_map(|s| s.parse().ok()).collect();
    let max_len = parts1.len().max(parts2.len());

    for i in 0..max_len {
        let p1 = parts1.get(i).copied().unwrap_or(0);
        let p2 = parts2.get(i).copied().unwrap_or(0);

        match p1.cmp(&p2) {
            Ordering::Equal => continue,
            other => return other,
        }
    }

    Ordering::Equal
}

// 查找匹配的安装包
fn find_matching_asset(assets: &[GitHubAsset], platform: &str, arch: &str) -> Option<String> {
    let rules = get_platform_match_rules(platform, arch)?;

    for asset in assets {
        let name_lower = asset.name.to_lowercase();

        // 检查文件扩展名
        if !name_lower.ends_with(rules.file_extension) {
            continue;
        }

        // 检查平台关键字
        if !rules
            .platform_keywords
            .iter()
            .any(|k| name_lower.contains(k))
        {
            continue;
        }

        // 检查架构关键字（如果指定）
        if !rules.arch_keywords.is_empty()
            && !rules.arch_keywords.iter().any(|k| name_lower.contains(k))
        {
            continue;
        }

        // 检查必需的关键字
        if !rules.required_keywords.is_empty()
            && !rules
                .required_keywords
                .iter()
                .all(|k| name_lower.contains(k))
        {
            continue;
        }

        log::info!("找到匹配的安装包: {}", asset.name);
        return Some(asset.browser_download_url.clone());
    }

    None
}

// 获取平台匹配规则
fn get_platform_match_rules(platform: &str, arch: &str) -> Option<PlatformMatchRules> {
    match platform {
        "windows" => Some(PlatformMatchRules {
            file_extension: ".exe",
            platform_keywords: &["win", "windows"],
            arch_keywords: if arch == "arm64" {
                &["arm64", "aarch64"]
            } else {
                &["x64", "amd64", "x86_64"]
            },
            required_keywords: &["setup"],
        }),

        "linux" => Some(PlatformMatchRules {
            file_extension: ".appimage",
            platform_keywords: &["linux"],
            arch_keywords: if arch == "arm64" {
                &["arm64", "aarch64"]
            } else {
                &["x64", "amd64", "x86_64"]
            },
            required_keywords: &[],
        }),

        "macos" => Some(PlatformMatchRules {
            file_extension: ".dmg",
            platform_keywords: &["macos", "darwin", "osx"],
            arch_keywords: if arch == "arm64" {
                &["arm64", "aarch64", "apple-silicon"]
            } else {
                &["x64", "intel", "amd64"]
            },
            required_keywords: &[],
        }),

        "android" => Some(PlatformMatchRules {
            file_extension: ".apk",
            platform_keywords: &["android"],
            arch_keywords: &[],
            required_keywords: &[],
        }),

        _ => None,
    }
}

// 获取平台名称
fn get_platform_name() -> String {
    std::env::consts::OS.to_string()
}

// 获取系统架构
fn get_architecture() -> String {
    match std::env::consts::ARCH {
        "aarch64" => "arm64".to_string(),
        "x86_64" => "x64".to_string(),
        arch => arch.to_string(),
    }
}

// ============================================================================
// 结果结构
// ============================================================================

#[derive(Debug, Serialize)]
pub struct UpdateCheckResult {
    pub current_version: String,
    pub latest_version: String,
    pub has_update: bool,
    pub download_url: Option<String>,
    pub release_notes: Option<String>,
    pub html_url: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version_comparison() {
        assert_eq!(compare_versions("1.0.0", "1.0.0"), Ordering::Equal);
        assert_eq!(compare_versions("1.0.0", "1.0.1"), Ordering::Less);
        assert_eq!(compare_versions("1.0.1", "1.0.0"), Ordering::Greater);
        assert_eq!(compare_versions("1.2.3", "1.10.0"), Ordering::Less);
        assert_eq!(compare_versions("2.0.0", "1.9.9"), Ordering::Greater);
    }

    #[test]
    fn test_platform_detection() {
        let platform = get_platform_name();
        assert!(!platform.is_empty());

        let arch = get_architecture();
        assert!(arch == "x64" || arch == "arm64");
    }
}
