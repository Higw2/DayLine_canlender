# 随手记验收（2026-10-02）

## 中文输入法修复补充

- 标题和正文改为保留原生 AppKit 编辑状态的文本控件。相同草稿的 SwiftUI 更新、便笺首次自动创建及列表刷新不再回写文本，不重置光标、选区或候选文字。
- 依据 [Apple 的 marked text API](https://developer.apple.com/documentation/appkit/nstextinputclient/setmarkedtext(_:selectedrange:replacementrange:)) 区分输入法组合文字与已确认文本。候选文字不触发自动保存；已确认文本正常进入 600ms 自动保存流程。
- 显式保存、切换、收起和退出前确认当前文本；自动保存不会强行结束输入法组合。仅新建、打开其他便笺或删除时更新草稿版本以加载不同内容，自动保存得到的便笺 ID 不影响编辑器身份。
- `swift test --scratch-path /private/tmp/dayline-ime-build`：31/31 通过。新增 4 项 AppKit 回归测试直接调用组合输入 API，覆盖候选文字等待期间跨过自动保存时点、模型旧值刷新、光标及组合区保持、确认中文后保存、显式保存组合文字、标题和草稿切换。
- 实际界面验收使用 `io.github.dayline.IMEQA.20261002` 和 `/private/tmp/dayline-ime-qa/data`：中文标题及多行正文保存；正文中间插入、等待自动保存后继续输入，光标仍位于原位置；撤销正常。系统拼音候选选择流程未作为人工验收结论，组合输入由上述 AppKit 回归测试验证。
- 发布构建、ZIP 校验和解压后严格签名检查通过。

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
