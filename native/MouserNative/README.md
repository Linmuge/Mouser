# Mouser for macOS

这是 Mouser 的 macOS SwiftUI 原生实现，仓库 fork 自 [TomBadash/Mouser](https://github.com/TomBadash/Mouser)，感谢原作者 Tom Badash。它兼容现有 `config.json`，并已原生实现辅助功能授权、滚轮/按键事件、CoreHID、HID++、DPI、SmartShift、棘轮/飞轮、滚轮反转、手势、操作环、触觉反馈、应用配置、截图和应用内更新。

项目使用 Xcode 27、Swift 6 语言模式和完整并发检查，最低系统版本为 macOS 27。

## 运行

```bash
cd native/MouserNative
xcodegen generate
open MouserNative.xcodeproj
```

或直接构建：

```bash
xcodebuild build \
  -project MouserNative.xcodeproj \
  -scheme MouserNative \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
```

生成 Developer ID 签名并公证的 Release 与 Debug DMG：

```bash
./release.sh
```

脚本只通过钥匙串配置 `Mouser-Notary` 调用 `notarytool`，不会读取或保存 Apple ID 密码。可用 `MOUSER_SIGN_IDENTITY`、`MOUSER_DEVELOPMENT_TEAM`、`MOUSER_NOTARY_PROFILE` 和 `MOUSER_VERSION` 覆盖发行参数。

GitHub 的原生测试与 Release 工作流均使用标签为 `mouser-release` 的受信任自托管 macOS runner，以确保使用 Xcode 27 和 macOS 27 SDK；测试任务不读取签名凭据，Developer ID 与公证凭据只由发行任务从该 runner 的钥匙串中使用。

## 设计原则

- 采用系统 `NavigationSplitView`、工具栏、菜单、开关、滑块与 SF Symbols。
- 左侧导航只表示任务；当前应用配置集中在工具栏，不再叠加第二套侧栏。
- 每个页面只解决一种问题，设备图仅用于按键选择和状态展示。
- 直接使用 macOS 27 的系统 Liquid Glass API。
- 原生配置层兼容现有版本 11 的配置结构，修改时保留无法识别的新字段。
- 英文、简体中文与繁体中文沿用旧版 `settings.language`，切换后立即更新窗口、菜单栏与操作环。
- 辅助功能状态来自 `AXIsProcessTrustedWithOptions`，窗口会自动重新检查授权变化。
- 原生滚轮引擎使用 `CGEvent.tapCreate`，同时处理 line、fixed-point 和 point 三套滚动 delta。
- 使用 macOS 27 typed notification message 监听唤醒与用户会话恢复，并通过 `IOConsoleLocked` 的锁定到解锁边沿补足普通锁屏路径。
- 每次恢复立即重建事件 tap，并在 1 秒、3 秒后进行有界重试；重复恢复信号会合并。
- 原生事件处理和 HID++ 设备控制按能力协同工作：滚轮可选择 HID++ 固件反转，也可在保持设备控制时使用 macOS 事件回退，避免重复反转。
- 设备发现使用 macOS 27 `CoreHID.HIDDeviceManager` 的异步通知流；HID++ 报告通过 `IOHIDDeviceOpen(..., kIOHIDOptionsTypeNone)` 非独占收发，不会 seize 设备。
- CoreHID 通知流在锁屏、睡眠或 USB 重置后结束时会清除陈旧设备状态并自动重新订阅。
- 界面严格区分“发现 USB/Bolt 接收器”和“识别到具体鼠标”，不会把接收器名称伪装成 MX Master。
- HID++ 长报告编解码、IRoot 功能发现，以及 SmartShift、DPI、触觉、电量命令已具备独立协议测试。
- HID++ 会话会匹配软件 ID、功能号和函数号，忽略无关按键/滚轮报告，并对设备错误和超时给出确定结果。
- 接收器槽位探测在正式版默认启用，可识别真实鼠标名称，读取 DPI、SmartShift、滚轮和电量状态，并把界面更改写入设备。
- 锁屏、唤醒和用户会话恢复后会重新建立 HID++ 会话，并重放 DPI、SmartShift 及横纵滚轮反转设置。
- 仓库包含需显式开启的真实 HID 验收测试；普通测试不会读写用户设备。
- macOS 发行流程仅构建 Swift 目标，不再打包 Python、PySide6 或 Qt 运行时；Python 实现继续服务 Windows/Linux。
