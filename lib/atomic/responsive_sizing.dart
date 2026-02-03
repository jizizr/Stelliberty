// 响应式布局工具类
// 根据屏幕尺寸决定 UI 布局

class ResponsiveSizing {
  // 判断是否应该显示侧边栏
  // 横屏（宽 > 高）显示侧边栏，竖屏显示底部导航
  static bool shouldShowSidebar(double width, double height) {
    return width > height;
  }

  // 判断是否应该显示底部导航
  static bool shouldShowBottomNav(double width, double height) {
    return !shouldShowSidebar(width, height);
  }
}
