<div align="center">

<img src="ubuntu/packaging/io.github.dayline.Calendar.svg" width="112" alt="DayLine logo">

# DayLine

**把今天的安排放回桌面。**

原生桌面日历与日程提醒应用：现已同时支持 **Ubuntu 24.04** 与 **macOS 13+** 原生桌面环境。

*A native, private and lightweight desktop calendar for Ubuntu & macOS.*

[![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04_LTS-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/desktop)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos)
[![Python 3](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![GTK 4](https://img.shields.io/badge/GTK-4-4A86CF?logo=gtk&logoColor=white)](https://www.gtk.org/)
[![Tests](https://img.shields.io/badge/tests-44_passing-2E7D32)](#测试)
[![GitHub stars](https://img.shields.io/github/stars/Higw2/ubuntu24-calendar?style=social)](https://github.com/Higw2/ubuntu24-calendar/stargazers)

[下载安装包](#-发布版本下载) · [功能亮点](#功能亮点) · [平台目录](#项目结构) · [从源码运行](#从源码运行)

</div>

## 📦 发布版本下载

在 GitHub [Releases](https://github.com/Higw2/ubuntu24-calendar/releases) 页面中，已为两套系统分别提供专属安装包：

| 系统平台 | 下载包名称 | 说明与安装方式 |
|---|---|---|
| **macOS (13.0+)** | **`DayLine-macOS.zip`** | 解压得到 `DayLine.app`，直接拖入 `/Applications`（应用程序）即可使用。 |
| **Ubuntu 24.04** | **`DayLine-Ubuntu-24.04.tar.gz`** | 解压后进入目录运行 `python3 install.py --autostart` 即可安装到应用菜单。 |

两套版本均使用独立的本地存储，互不冲突，数据结构完全兼容。

## 为什么是 DayLine？

很多日历适合“打开后查看”，DayLine 更关注日程如何融入 Ubuntu 桌面。主窗口用于规划，桌面卡片负责陪伴，提醒窗口确保重要安排不会被错过。

- **真正的日时间线**：事件按照开始分钟定位，卡片高度对应持续时间；在空白处拖拽即可按 15 分钟选中时段并创建事件。
- **自由调整布局**：日历侧栏与时间表之间提供可拖动分隔条，比例会自动保存；窗口缩放和竖屏布局会按比例重新适配。
- **Ubuntu 随手记**：在「日程」与「随手记」之间切换，创建、编辑和删除纯文本便笺，内容自动保存到本地 SQLite 数据库。
- **返回今天与更新**：打开主窗口会回到今天；Ubuntu 版可自动检查 GitHub Release，并在设置中下载、校验和安装更新。
- **桌面常驻卡片**：查看近期安排和实时时钟，无需反复打开主窗口；支持拖动、缩放，并记住位置和尺寸。
- **可靠提醒**：主窗口关闭后继续运行，到点同时显示应用内弹窗和系统通知；支持完成或延后 10 分钟。
- **按自己的风格显示**：8 种强调色、自由调色板、3 种桌面卡片主题和 4 档字体缩放，修改后立即生效。
- **背景随心切换**：纯色与本地图片背景、7 种背景预设、自定义颜色、20%–100% 透明度和应用内毛玻璃效果。
- **本地优先**：日程、便笺和偏好设置只保存在本机，记录与排程可离线使用；开启更新检查时仅访问 GitHub Release。
- **轻量原生**：Python + GTK4 + Libadwaita，无 Electron、无 npm、无额外 pip 依赖。

## 功能亮点

### Outlook 式日视图

DayLine 使用连续 24 小时时间轴，而不是简单的待办列表。09:15 开始的事件会出现在 09:15，持续两小时的事件会覆盖两小时高度。当多个事件发生在同一时间段，它们会自动分列，仍然可以分别查看和操作。在时间线空白处按住鼠标拖动，松开后会直接打开新建窗口，并自动填入所选的开始与结束时间。

日历和时间表之间的分隔条可以直接拖动，按照自己的习惯分配两侧空间。拖动范围会保留两侧可用空间；比例会保存下来，横向缩放或切换到竖屏窗口时自动重新计算，时间线会使用当前可用宽度绘制。

打开主窗口时，左侧日历和时间线都会回到今天；点击“返回今天”还会定位到当前时刻。只有分隔条本身可以拖动，日历内容不会触发分栏调整。

### Ubuntu 随手记

在主窗口切换「日程」与「随手记」，可创建、编辑或删除纯文本便笺；桌面卡片也有新建便笺快捷入口。标题可以留空，应用会用正文首行作为标题，并随内容更新。编辑内容会自动保存到本地 SQLite 数据库，重新打开应用后仍可继续查看。

### Ubuntu 应用内更新

已安装的 Ubuntu 版默认每天检查一次 GitHub Release。发现新版本时会发出通知；在「设置 → 软件更新」中可立即检查、选择检查频率，或点击「下载并安装」。应用会校验 GitHub 提供的 SHA-256 摘要，再安装到当前用户的 `~/.local` 目录并重新启动。日程数据库和个人设置不会被安装器覆盖。源码直接运行时可以检查更新，但应用内安装需要先运行 `python3 ubuntu/install.py`。

发布者需要使用比已安装版本更高的 `v主版本.次版本.修订号` 标签，并上传文件名**完全一致**的 `DayLine-Ubuntu-24.04.tar.gz`。完整步骤见 [Ubuntu Release 发布说明](ubuntu/README.md#发布可被自动更新识别的-release)。旧版没有更新模块，需先手动安装一次带更新功能的版本。

### 一眼可见的桌面日程

点击“收起到桌面”，主窗口会隐藏，DayLine 继续显示近期安排并在后台检查提醒。

- 拖动顶部把手调整位置
- 拖动右下角调整卡片大小
- 自动保存位置和尺寸
- 顶部居中显示实时时钟
- 从卡片直接新建事件、打开主窗口或进入设置

### 事件与提醒

- 创建、编辑、删除和完成事件
- 支持备注、跨日事件和多个重叠事件
- 到点显示独立提醒弹窗和系统通知
- 支持“10 分钟后提醒”
- 提醒状态持久化，重启后不会重复弹出已处理提醒
- 恢复运行后补发 24 小时内错过的提醒

### 个性化

- 8 种预设强调色，也可以自由选色
- 深邃墨夜、跟随主题、清爽明亮三种桌面背景
- 90%、100%、115%、130% 四档字体大小
- 主窗口和桌面卡片实时同步更新
- 纯色 / 图片背景随时切换，图片仅显示文件名
- 图片使用 aspect-fill 裁切和柔和毛玻璃模糊

## 安装

### 1. 获取代码

```bash
git clone https://github.com/Higw2/ubuntu24-calendar.git
cd ubuntu24-calendar
```

### 2. 安装系统依赖

Ubuntu 24.04 通常已经包含其中大部分组件：

```bash
sudo apt update
sudo apt install python3 python3-gi python3-gi-cairo gir1.2-gtk-4.0 gir1.2-adw-1
```

### 3. 安装 DayLine

```bash
python3 ubuntu/install.py --autostart
```

安装完成后，在 Ubuntu 应用列表中搜索 **DayLine**。`--autostart` 会让桌面卡片在登录后自动出现；如果不需要自启动，运行 `python3 ubuntu/install.py` 即可。

安装只影响当前用户，不需要 `sudo`：

| 内容 | 位置 |
|---|---|
| 应用文件 | `~/.local/lib/dayline` |
| 启动器 | `~/.local/bin/dayline` |
| 日程数据库 | `~/.local/share/dayline/events.db` |
| 偏好设置 | `~/.config/dayline/settings.json` |
| 桌面卡片位置与尺寸 | `~/.config/dayline/desktop-position` |

## 直接运行

想先体验而不安装，可以在项目目录运行：

```bash
./run.sh
```

其他启动方式：

```bash
./run.sh --desktop   # 只显示桌面卡片
./run.sh --quit      # 退出正在运行的 DayLine
./run.sh --help      # 查看帮助
```

`run.sh` 会自动定位项目目录，因此可以从任意工作目录调用。

## 日常使用

1. 打开 DayLine，在左侧日历中选择日期。
2. 在时间线空白处拖拽选择时段，或点击“新建事件”，填写名称与备注。
3. 在时间线上完成、编辑或删除事件。
4. Ubuntu 版可切换到「随手记」，记录和整理纯文本便笺。
5. 点击“收起到桌面”，让卡片留在桌面并继续接收提醒。
6. 按住卡片顶部拖动；使用右下角手柄调整大小。

关闭主窗口只会收起到桌面。若要停止后台提醒，请点击“退出 DayLine”或运行 `./run.sh --quit`。

## 桌面兼容性

| 会话 | 日程与提醒 | 桌面背景层 | 拖动与尺寸记忆 |
|---|---:|---:|---:|
| Ubuntu 24.04 GNOME X11 / Ubuntu on Xorg | ✅ | ✅ | ✅ |
| GNOME Wayland | ✅ | 普通常驻窗口 | 由窗口管理器控制 |

完整桌面模式目前以 **Ubuntu 24.04 GNOME X11** 为目标。X11 下，卡片会设置桌面窗口、置底、跨工作区并跳过任务栏和窗口切换器。

Wayland 不允许普通应用自行进入 GNOME 桌面背景层，因此 DayLine 会降级为普通窗口，日程和提醒仍可使用。如果需要完整桌面体验，可以在登录界面的齿轮菜单中选择 **Ubuntu on Xorg**。

## 数据与隐私

DayLine 不上传日程、便笺或壁纸。事件和 Ubuntu 版便笺保存在本地 SQLite 数据库中，主题、字体、桌面布局及所选壁纸的本地路径保存在配置文件中。DayLine 不会复制或上传壁纸原文件；启用更新检查时会访问 GitHub Release API。

备份时先退出 DayLine，再复制：

```bash
cp ~/.local/share/dayline/events.db ~/dayline-events-backup.db
```

卸载应用：

```bash
python3 ubuntu/install.py --uninstall
```

卸载会移除应用文件、启动器和自启动项，同时保留日程数据库，避免误删用户数据。

## 测试

```bash
PYTHONPATH=ubuntu python3 -m unittest discover -s ubuntu/tests -v
python3 -m py_compile ubuntu/dayline/*.py ubuntu/tests/*.py ubuntu/install.py ubuntu/update_helper.py
```

当前测试覆盖事件与便笺存储、提醒状态、跨日裁切、分钟定位、拖拽选区、重叠分列、短事件、竖屏分栏、分隔条限位、自适应宽度、背景配置、主题生成、设置持久化、更新版本选择与下载校验及桌面窗口几何信息。当前版本共有 **44 项测试**。

详细的真实桌面验收记录见 [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md)。

## 项目结构

整个仓库清晰划分为 Ubuntu 与 macOS 两个原生实现目录：

```text
DayLine/
├── ubuntu/                    # Ubuntu 24.04 原生版 (Python 3.12 / GTK4 / Libadwaita)
│   ├── dayline/               # Python 应用模块 (界面、时间线、桌面卡片、提醒、存储)
│   ├── packaging/             # 桌面图标与 SVG 资源
│   ├── tests/                 # 单元测试集 (存储、时间线、设置)
│   ├── install.py             # 免 sudo 用户级安装器
│   ├── run.sh                 # Ubuntu 直接运行脚本
│   ├── package.sh             # 打包为 DayLine-Ubuntu-24.04.tar.gz
│   └── README.md              # Ubuntu 专属说明文档
├── macos/                     # macOS 13+ 原生版 (Swift 5.10 / AppKit / SwiftUI)
│   ├── Sources/DayLineApp/    # 原生应用主窗口、桌面卡片、提醒悬浮窗、单实例锁
│   ├── Sources/DayLineCore/   # SQLite 存储、时间线吸附与重叠布局算法、模型
│   ├── Sources/CSQLite/       # 系统 SQLite module map
│   ├── Tests/DayLineCoreTests/# Swift 核心测试套件
│   ├── scripts/build-app.sh   # 编译并生成 DayLine-macOS.zip
│   ├── scripts/run.sh         # macOS 独立运行脚本
│   ├── Package.swift          # SwiftPM 配置
│   ├── README.md              # macOS 专属说明文档
│   └── ACCEPTANCE.md          # macOS 全功能实机验收记录
├── scripts/
│   └── package-all.sh         # 一键同时打包 Ubuntu 与 macOS 发布包至 dist/
├── docs/                      # 架构设计与验收标准
└── run.sh                     # 根目录运行入口 (自动识别操作系统并启动对应版本)
```

## Roadmap

- [ ] 周视图与月视图
- [ ] 重复事件
- [ ] `.ics` 导入与导出
- [ ] 提前 5/15/30 分钟提醒
- [ ] Flatpak / `.deb` 安装包
- [ ] Wayland 下的 GNOME Shell 扩展
- [ ] 更多语言

欢迎通过 [Issues](https://github.com/Higw2/ubuntu24-calendar/issues) 提交建议或报告问题，也欢迎直接发送 Pull Request。

## 参与贡献

```bash
git clone https://github.com/Higw2/ubuntu24-calendar.git
cd ubuntu24-calendar
git checkout -b feature/your-feature
```

提交前请运行测试，并在 Pull Request 中说明改动内容和验证方式。对于界面改动，附上前后截图会更容易评审。

---

<div align="center">

如果 DayLine 让你的 Ubuntu 桌面更好用，欢迎点一个 ⭐。你的 Star 会帮助更多人发现这个项目。

**Made for Ubuntu desktops with Python, GTK4 and Libadwaita.**

</div>
