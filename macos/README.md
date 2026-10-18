# DayLine for macOS

这是 DayLine 的独立 macOS 13+ 原生实现。它与仓库中的 Ubuntu 24.04（GTK4/Python）版本并存，所有代码、构建产物和运行数据路径均独立；没有第三方依赖。

## 功能

- 24 小时日视图：按分钟定位、15 分钟向外吸附拖拽新建、跨日裁切；短于 32 分钟的卡片仍参与重叠分列。
- 事件完整操作：新建、双击编辑、删除、完成、备注和跨日事件。
- 事件边缘拖拽：拖动卡片上边缘修改开始时间、下边缘修改结束时间，按 15 分钟吸附，显示实时预览，松手保存；Esc 取消。拖拽后至少保留 15 分钟，支持当天 00:00–24:00，跨日事件只调整当前日内可见的真实端点。
- 随手记：侧栏切换到独立便笺页，支持新建、编辑、删除确认；输入停止 600ms 后自动保存，也可手动保存或按 Command-S。标题可留空，自动取正文首个非空行；列表按最后修改时间排列。切换便笺、回到日程、收起窗口和退出前都会保存草稿。
- 桌面卡片：显示未完成且尚未结束的近期 5 条、秒级时钟、位置和尺寸记忆；关闭主窗口会收起至卡片，状态栏菜单可恢复。
- 默认提前 5 分钟弹出“事件即将开始 / 知道了”；到设定时间只发送系统通知，已删除原来的“推迟 10 分钟 / 已完成”独立弹窗。可在偏好设置的“事件提醒”中选择提前 5、10、15 或 30 分钟。到点系统通知需要允许 DayLine 的 macOS 通知权限；完成和时间调整可在时间线操作。
- 每 3 秒检查提醒，两阶段状态分别保存在 SQLite，重启不会重复投递已触发的提醒。错过预提醒且开始时间已到时，只补发到点系统通知；过去 24 小时内漏掉的到点提醒会补发，更早的提醒静默确认。应用需保持运行（可收起到桌面）；电脑休眠或应用退出期间不会投递提醒。
- 设置：8 个强调色与自选颜色、深色/色调/明亮三种卡片主题、90/100/115/130% 字体缩放，均即时保存。可在设置中请求登录启动（macOS 可能要求在系统设置确认）。
- 主窗口分区：拖动侧栏和时间线之间的细分隔线即可分配空间，比例会保存到 `settings.json`。窗口宽度小于 960pt 或高于宽度时，界面会自动改为上下分区；窗口尺寸恢复后会继续使用已保存的比例。
- 自适应月历：侧栏月历始终显示六行、周一至周日的 42 个日期格，会随分区和窗口宽度扩展；相邻月日期可直接选择。
- 自适应时间线：右侧日视图会填满可用宽度，仅垂直滚动；纵轴固定为每分钟 1pt，拖拽新建仍按 15 分钟吸附。
- 单实例：同一个数据目录只允许一个运行实例，后续实例会唤醒正在运行的实例。

## 构建与运行

需要 Xcode 15.3 或更新版本（Swift 5.10 模式），并在 macOS 上执行：

```zsh
cd macos
./scripts/build-app.sh
open build/DayLine.app
```

`./scripts/run.sh` 会先构建，再从 `.app` 内运行，确保系统通知拥有正确的 Bundle 身份。构建结果为 `build/DayLine.app` 与可分发的 `build/DayLine-macOS.zip`，使用本地临时签名 `codesign --sign -`。日常安装请解压 zip 后将 `.app` 拖入 `/Applications`；登录启动项由 macOS 按固定的安装位置管理。

命令行参数：

```zsh
./scripts/run.sh --help       # 仅显示帮助，不创建数据库
./scripts/run.sh --desktop    # 只显示桌面卡片
./scripts/run.sh --quit       # 退出已在运行的同一数据目录实例
```

测试：

```zsh
cd macos
swift test --scratch-path /private/tmp/dayline-tests
```

## 数据位置与 Ubuntu 数据迁移

默认数据目录是：

```text
~/Library/Application Support/DayLine/
├── events.db       # 与 Ubuntu 版兼容的 SQLite events、notes 表
├── settings.json
└── geometry.json
```

先退出两个 DayLine 应用，再显式复制 Ubuntu 数据库：

```zsh
mkdir -p "$HOME/Library/Application Support/DayLine"
cp "$HOME/.local/share/dayline/events.db" "$HOME/Library/Application Support/DayLine/events.db"
```

不会自动读取或修改 Ubuntu 数据库。验收、开发和隔离运行可使用 `DAYLINE_DATA_DIR`：

```zsh
cd macos
DAYLINE_DATA_DIR=/private/tmp/dayline-demo ./scripts/run.sh
```

同一 `DAYLINE_DATA_DIR` 下为一个单实例；不同目录彼此独立。

## 操作提示

- 时间线空白处拖拽以创建事件；双击卡片编辑；按住 Command 单击卡片即可完成。
- 卡片顶部和底部的短横线为时间调整手柄；拖动时会显示起止时间，松手保存，按 Esc 取消。重叠事件仍可分别调整，标题、备注和完成状态保留。
- 点击“收起到桌面”或关闭主窗口后，桌面卡片和提醒仍继续运行。
- 桌面卡片可拖动和缩放。若显示器变更，显示时会自动将其移回可见区域。
- 桌面卡片的便笺图标、状态栏菜单“新建便笺”，或 Command-Shift-N 可直接打开新的便笺；文本编辑支持标准剪切、复制、粘贴和撤销快捷键。
- 完全退出请从桌面卡片、状态栏菜单或应用菜单选择“退出 DayLine”。

## 项目结构

```text
macos/
├── Sources/DayLineCore/      # SQLite、模型、布局、设置
├── Sources/DayLineApp/       # AppKit 窗口、SwiftUI、提醒、单实例
├── Sources/CSQLite/          # 系统 SQLite module map
├── Tests/DayLineCoreTests/   # 模型/布局/提醒/设置测试
└── scripts/                  # 构建 app 与运行脚本
```
