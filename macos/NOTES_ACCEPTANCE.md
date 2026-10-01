# 随手记验收（2026-10-02）

## 实现

- macOS 独立便笺页，侧栏“随手记”切换，桌面卡片及菜单可新建便笺。
- 与 Ubuntu 的 `notes` 表兼容；旧表缺少 `auto_title` 时补充字段，保留已有日程。
- 标题可选，取正文首个非空行作为自动标题；保留正文原有换行及空白。
- 输入停止 600ms 后保存；切换便笺、新建、回到日程、收起主窗口及正常退出前立即保存。
- 保存失败保留草稿并提示，阻止会丢弃草稿的切换和退出；删除前确认。
- 便笺列表和编辑器可拖动分隔线；可用宽度小于 620pt 时改为上下分栏。

## 自动化与构建

- `swift test --scratch-path /private/tmp/dayline-notebook-build`：27/27 通过。
- 新增 8 项测试覆盖便笺 CRUD、标题规则、排序、持久化、Ubuntu 旧表迁移、草稿切换、失败保留、空白便笺、自动保存及删除时取消待保存任务。
- `PYTHONPATH=ubuntu python3 -m unittest ubuntu.tests.test_notes`：8/8 通过。
- `./scripts/build-app.sh`：发布构建通过；ZIP 的 SHA-256 校验通过；原应用清理 Finder 扩展属性后以及 ZIP 解压副本均通过 `codesign --verify --deep --strict`。

## 实际界面

验收使用独立 bundle ID `io.github.dayline.NotebookQA.20261002`，数据目录 `/private/tmp/dayline-notebook-qa/data`。

- 多行输入自动保存至 SQLite，自动生成标题。
- 新建第二条便笺、设置手动标题、直接切换，草稿保存并恢复目标内容。
- 修改自动标题便笺正文、Command-S 保存，列表标题随首行更新。
- 删除确认显示当前标题；取消后内容与数量保留。实际删除由自动化存储及编辑器测试覆盖。
- 切回日程正常；Command-Shift-N 新建空白便笺。
- 输入后立即 Command-Q 正常退出，草稿落库；重启后可打开完整内容。
- 隔离配置的侧栏比例调至 55%，右侧约 504pt，便笺自动采用上下分栏，编辑器填满剩余空间。
- 收起至桌面后可从便笺图标返回新的空白便笺。

## Git

推送拒绝原因是远端 `main` 有本地未合并的提交 `841e997`，不是认证失败。获取远端后无冲突合并为 `bdc498a`，保留本地事件操作和远端 Ubuntu 功能。`git push --dry-run` 已通过，未执行实际推送。
