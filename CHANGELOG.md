# 20261114

- `Add-UploadQueue` 默认改为 `-QueueKey biliup:render-list`、`-FileNameStyle Leaf`，source/拆分文件统一走 Node-RED `biliup 直接 v2`。
- 禁用了旧的 `biliup:upload-list` Node-RED flow；不再使用 `输出` 目录里的旧 `biliup-cli 0.2.4` 和旧 cookies。
- `Add-UploadQueue` 队列项默认只写 `filename` 和 `bvid`，不再写 Windows 的 `X:\...` `path` 字段；需要附加字段时用 `-Metadata`。
- `Split-Video -OnlyInner` 恰好两个时间点时增加 `-ss`/`-t` 快速路径，不再先处理整个文件。
- segment muxer 没有 `total_size` 时进度显示 `size=N/A`，不再显示 `0kB`。
- `RenderVideo` 模块版本提升到 1.4.0，`PerfectBili.Common` 模块版本提升到 1.1.3。
- 补充直接上传流程、`SOURCE_DIR` 和 Redis 排查说明。

# 20261113

- `PerfectBili.Common` 新增 `Add-UploadQueue`，支持 `Split-Video` / `Invoke-VideoRender` 管道入队。
- `Invoke-RedisCli` 支持 `-RedisPort` / `-RedisDatabase`，并固定 UTF-8 输入。
- `PerfectBili.Common` 模块版本提升到 1.1.0。

# 20261103

- `Split-Video` 新增 `-OnlyInner`（别名 `-ExcludeEnds`）：只输出内部区间，不输出 0→t1 和 tN→end。
- `RenderVideo` 模块版本提升到 1.3.0。

# 20261031

- 抽出 `RenderVideo` 模块：编码、快速拆分、媒体信息、环境检查、实时进度。
- `render_video.ps1` 迁移到模块，配置外置到 `render.config.psd1`。
- `upload_video.ps1` 配置外置到 `upload.config.psd1`，失败任务进入 `biliup:upload-failed`。
- 新增 `PerfectBili.Common` 公共模块，统一日志、通知和 Redis CLI。
- 新增 `enqueue_render.ps1`，拖拽 `.bat` 改为调用它。
- PowerShell 脚本统一 UTF-8 with BOM；整理 `docs/` 和 README。

# 20250817
obs 启动脚本时报错了
`CDLL(find_library("obs"))`，所以改成 `CDLL("obs")` 即可

[Python Scripting - Pulling audio source information](https://obsproject.com/forum/threads/python-scripting-pulling-audio-source-information.142254/)
