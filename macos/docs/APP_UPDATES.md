# DayLine macOS 应用内更新

DayLine 会从 GitHub Releases 查询新的 macOS 版本。设置中的“自动检查更新”默认关闭，用户开启后可选择每 6 小时、每天或每周检查。发现新版本时，用户可在应用内下载、校验、替换应用并自动重新打开；日历数据库和设置文件不会随应用包替换。

## 发布要求

1. 使用三段式语义版本号构建，例如：

   ```zsh
   DAYLINE_VERSION=1.0.1 DAYLINE_BUILD_VERSION=2 ./scripts/build-app.sh
   ```

2. 创建同版本 GitHub Release，标签使用 `v1.0.1`。若标签需要不同名称，构建时同时传入 `DAYLINE_RELEASE_TAG`，确保应用包记录的标签与 Release 一致。
3. 将 `build/DayLine-macOS.zip` 上传为 Release asset，文件名必须保持不变。GitHub API 必须为该 asset 返回 `sha256:` 摘要，否则客户端会拒绝安装。
4. 不要将 macOS 包只附加到 Ubuntu Release。客户端会在最近 20 个正式 Release 中查找包含 `DayLine-macOS.zip` 的更高语义版本。

当前 `1.0.0` 构建兼容已有的 `Macos_version` 标签，并将其视为当前版本，不会在首次检查时误报更新。

## 安装校验

客户端只接受 HTTPS 下载，并依次检查 Release 中的文件大小、GitHub 提供的 SHA-256、应用 bundle identifier、应用版本和 macOS 代码签名。校验通过后，独立的更新辅助程序才会替换当前 `.app`。如果应用所在目录不可写，客户端会停止更新并显示错误，不会删除当前版本。
