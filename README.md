# 时序 · Dayline

为 Ubuntu 24.04 LTS 打造的本地桌面日程表：在时间线上安排一天，让日程留在桌面，到点弹窗提醒。

## 启动

```bash
./run.sh
```

仅显示桌面日程可运行 `./run.sh --desktop`；退出正在运行的应用可运行 `./run.sh --quit`。

应用使用系统 Python、GTK4 和 Libadwaita，不需要 npm、在线账号或云服务。若系统缺少依赖：

```bash
sudo apt install python3 python3-gi python3-gi-cairo gir1.2-gtk-4.0 gir1.2-adw-1
```

请在 Ubuntu 图形桌面中运行。`run.sh` 可从任意工作目录启动。

## 安装到应用列表

```bash
python3 install.py
```

随后在 Ubuntu 应用列表搜索 **时序日程** 或 **Dayline**。如需登录后自动显示桌面日程：

```bash
python3 install.py --autostart
```

安装为当前用户进行，无需 sudo。程序安装到 `~/.local/lib/dayline`，启动器位于 `~/.local/bin/dayline`。修改源码后重新运行安装器即可更新。

## 日常使用

- 在主窗口中选择日期，点击“新建事件”填写名称、开始及结束时间与备注。
- 主窗口提供 24 小时日视图：事件按开始分钟定位，并按持续时间占据高度；相互重叠的事件会像 Outlook 一样并列显示。事件旁提供编辑、删除和标记完成按钮。
- 桌面模式显示当天日程，并提供打开主应用和新建事件的入口。
- 关闭主窗口后应用继续运行；使用应用内的退出操作才会停止后台提醒。
- 到点显示提醒弹窗，可标记完成或延后提醒。提醒状态保存在本地，重启不会重复提醒已经处理的事件。

## 桌面兼容性

Ubuntu 24.04 的 **GNOME X11（Ubuntu on Xorg）** 是完整桌面背景模式的目标环境。应用为独立桌面窗口设置置底、跨工作区和隐藏任务栏属性，编辑窗口保持正常操作。

在 **Wayland** 会话中，应用降级为普通常驻窗口；日程与提醒仍可使用，但不提供真正的桌面背景层。若需要完整桌面模式，可在登录界面选择“Ubuntu on Xorg”。窗口类型与层级实现依据 [EWMH 规范](https://specifications.freedesktop.org/wm/latest-single/) 和 [GTK X11 接口](https://docs.gtk.org/gdk4-x11/method.X11Surface.get_xid.html)。

提醒需要应用正在运行。电脑关机或挂起期间不会弹窗；恢复后的补发策略见下方实现说明。系统通知可能受勿扰模式影响，应用也会显示独立提醒窗口。

提醒按本机日期和时间运行。未处理且错过不超过 24 小时的提醒会在恢复运行后补发；超过 24 小时的旧提醒不再弹窗。手动创建过去时间的事件只记入日程，不补发提醒。提醒窗口提供“10 分钟后”选项。

## 数据与卸载

日程保存为本地 SQLite 数据库，不会上传。默认位置是 `~/.local/share/dayline/events.db`，设置 `XDG_DATA_HOME` 时为 `$XDG_DATA_HOME/dayline/events.db`。备份前先退出应用，再复制数据库文件。

```bash
python3 install.py --uninstall
```

卸载移除程序、应用列表入口和登录自启动项，保留日程数据库。若安装时使用自定义 `--prefix` 或 `--config-dir`，卸载时使用相同参数。

## 验证

```bash
python3 -m unittest discover -s tests -v
```

实际验收范围及结果见 [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md)。

新版日视图的实测截图见 [重叠事件](docs/screenshots/timeline-overlaps.png)、[跨日事件](docs/screenshots/timeline-cross-day.png) 和 [最小窗口](docs/screenshots/timeline-minimum-window.png)。

初版由 Astra 规划、Terra high 编码、Sol medium 验收；Outlook 式时间线由 Sol medium 规划、Luna high 编码并由 Sol medium 复验。
