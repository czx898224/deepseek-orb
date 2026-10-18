# Changelog

## v1.0.0

首个可发布版本。

### 功能
- 通体蓝色悬浮球：分层窗口（`UpdateLayeredWindow`）逐像素透明 + 柔和投影，150% DPI 自适应
- 单击开合面板、拖动记忆位置、右键菜单
- 面板 = Edge 应用窗加载 `chat.deepseek.com`，独立 profile 持久登录
- 面板三级窗口识别：启动进程 MainWindowTitle → 命令行 profile → 目标矩形兜底
- 全局热键（默认 `Ctrl+Alt+D`）
- 全屏检测（`SHQueryUserNotificationState`）自动隐藏球
- 游戏模式、无边框面板（Win11 圆角）、关闭面板进程
- 开机自启走启动文件夹快捷方式，不依赖 `wscript` / `.vbs`
- 单实例互斥、配置持久化、`orb.log` 日志

### 修复
- 旧版开机自启写 `wscript.exe …vbs`，在 `.vbs` 关联损坏的机器上开机报错 → 改为启动文件夹快捷方式，并在启动时自动迁移旧注册表项
- WinForms 自动缩放导致球窗口尺寸被除以 DPI → 改用 `SetWindowPos` 直接下发布局
- Edge 路径只认 x86 → 自动探测 x86 / x64 / 用户级安装 / 注册表 App Paths
