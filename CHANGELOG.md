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
