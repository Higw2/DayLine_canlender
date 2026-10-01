<div align="center">

<img src="packaging/io.github.dayline.Calendar.svg" width="112" alt="DayLine logo">

# DayLine

**把今天的安排放回桌面。**

一款为 Ubuntu 24.04 打造的原生日程应用：Outlook 式日视图、桌面常驻卡片与可靠的到点提醒。

*A native, private and lightweight desktop calendar for Ubuntu.*

[![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04_LTS-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/desktop)
[![Python 3](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![GTK 4](https://img.shields.io/badge/GTK-4-4A86CF?logo=gtk&logoColor=white)](https://www.gtk.org/)
[![Tests](https://img.shields.io/badge/tests-44_passing-2E7D32)](#测试)
[![GitHub stars](https://img.shields.io/github/stars/Higw2/ubuntu24-calendar?style=social)](https://github.com/Higw2/ubuntu24-calendar/stargazers)

[快速安装](#安装) · [功能亮点](#功能亮点) · [桌面兼容性](#桌面兼容性) · [参与贡献](#参与贡献)

</div>

## 为什么是 DayLine？

很多日历适合“打开后查看”，DayLine 更关注日程如何融入 Ubuntu 桌面。主窗口用于规划，桌面卡片负责陪伴，提醒窗口确保重要安排不会被错过。

- **真正的日时间线**：事件按照开始分钟定位，卡片高度对应持续时间；在空白处拖拽即可按 15 分钟选中时段并创建事件。
- **自由调整布局**：日历侧栏与时间表之间提供可拖动分隔条，比例会自动保存；窗口缩放和竖屏布局会按比例重新适配。
- **随手记**：在「日程」与「随手记」之间切换，创建、编辑和删除纯文本便笺，内容自动保存到本地 SQLite 数据库。
- **返回今天与更新**：打开主窗口会回到今天；可自动检查 GitHub Release，并在设置中下载、校验和安装更新。
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

### 随手记

在主窗口切换「日程」与「随手记」，可创建、编辑或删除纯文本便笺；桌面卡片也有新建便笺快捷入口。标题可以留空，应用会用正文首行作为标题，并随内容更新。编辑内容会自动保存到本地 SQLite 数据库，重新打开应用后仍可继续查看。

### 应用内更新

已安装版默认每天自动查询一次 GitHub Release。发现新版本会显示系统通知，在「设置 → 软件更新」可立即检查、修改检查频率、关闭自动检查，或点击「下载并安装」。DayLine 会下载 Ubuntu 专用包、校验 GitHub 提供的 SHA-256 摘要，退出旧进程后安装并重新启动。安装器只替换应用文件，保留 `~/.local/share/dayline/events.db` 和 `~/.config/dayline/settings.json`。直接运行源码时可以检查版本，但要在应用内安装更新，需先运行 `python3 install.py`。

没有更新功能的旧版不能自行升级，首次需要手动安装此功能之后发布的安装包。

### 发布可被自动更新识别的 Release

1. 确认 `ubuntu/VERSION` 为本次版本 `1.0.1`；今后每次发布都把它改成更高的三段数字版本。
2. 在 Ubuntu 上运行 `bash ubuntu/package.sh`，确认 `dist/DayLine-Ubuntu-24.04.tar.gz` 已生成。macOS 包如要一起发布，在 macOS 上用相同版本运行 `DAYLINE_VERSION=1.0.1 macos/scripts/build-app.sh`。
3. 提交版本文件和代码，并把指向该提交的标签 `v1.0.1` 推送到 GitHub；在仓库的 [Releases](https://github.com/Higw2/ubuntu24-calendar/releases) 页面为此标签创建 Release。
4. 上传 **`DayLine-Ubuntu-24.04.tar.gz`**（需要 macOS 时再上传 `DayLine-macOS.zip`），然后发布为正式 Release。草稿、预发布和仅有源码压缩包都不会被 Ubuntu 更新器采用。

更新器从最新 20 个 Release 中选择版本号最高且含有指定 Ubuntu 包的正式版。GitHub API 为上传的资源提供 SHA-256 `digest`；缺少该摘要时会停止安装。旧的 `Ubuntu24.04_version` 的标签和名称都没有三段版本号，因此不会触发更新；若当前安装版为 `1.0.0`，首个可识别的新标签可以是 `v1.0.1`。发布后打开 DayLine 的「设置 → 软件更新 → 立即检查」，验证能够显示新版本及「下载并安装」。[GitHub Release 管理文档](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository) · [Release API 文档](https://docs.github.com/en/rest/releases/releases)

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
python3 install.py --autostart
```

安装完成后，在 Ubuntu 应用列表中搜索 **DayLine**。`--autostart` 会让桌面卡片在登录后自动出现；如果不需要自启动，运行 `python3 install.py` 即可。

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
4. 切换到「随手记」，记录和整理纯文本便笺。
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

DayLine 不上传日程、便笺或壁纸。事件和便笺保存在本地 SQLite 数据库中，主题、字体、桌面布局及所选壁纸的本地路径保存在配置文件中。DayLine 不会复制或上传壁纸原文件；启用更新检查时会访问 GitHub Release API。

备份时先退出 DayLine，再复制：

```bash
cp ~/.local/share/dayline/events.db ~/dayline-events-backup.db
```

卸载应用：

```bash
python3 install.py --uninstall
```

卸载会移除应用文件、启动器和自启动项，同时保留日程数据库，避免误删用户数据。

## 测试

```bash
python3 -m unittest discover -s tests -v
python3 -m py_compile dayline/*.py tests/*.py install.py update_helper.py
```

当前测试覆盖事件与便笺存储、提醒状态、跨日裁切、分钟定位、拖拽选区、重叠分列、短事件、竖屏分栏、分隔条限位、自适应宽度、背景配置、主题生成、设置持久化、更新版本选择与下载校验及桌面窗口几何信息。当前版本共有 **44 项测试**。

详细的真实桌面验收记录见 [docs/ACCEPTANCE.md](../docs/ACCEPTANCE.md)。

## 项目结构

```text
dayline/
├── ui.py               # 主窗口与事件编辑器
├── timeline.py         # 分钟级时间线和重叠布局
├── desktop.py          # 桌面卡片与 X11 集成
├── reminders.py        # 提醒调度与弹窗
├── storage.py          # SQLite 事件存储
├── settings.py         # 偏好设置持久化
├── settings_dialog.py  # 设置窗口
└── theme.py            # 动态主题生成
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
