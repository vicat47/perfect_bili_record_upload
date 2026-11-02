# Windows 脚本

## 依赖

- Windows PowerShell 5.1 或 PowerShell 7+
- ffmpeg / ffprobe（`Test-RenderEnvironment` 会检查 NVENC）
- redis-cli
- biliup（上传端）

## 初始化配置

```powershell
Copy-Item .\render.config.example.psd1 .\render.config.psd1
Copy-Item .\upload.config.example.psd1 .\upload.config.psd1
# 然后编辑两个配置文件
```

`render.config.psd1` 和 `upload.config.psd1` 已被 `.gitignore` 忽略，不会提交。

通知统一使用 `{ "target": "...", "content": "..." }` JSON，`NotifyUrl` 填完整的 webhook 地址。

## 渲染端

```powershell
# 检查配置、ffmpeg、redis-cli，不连接 Redis
.\render_video.ps1 -ValidateOnly

# 常驻，等待新任务
.\render_video.ps1 -waitForNewTask

# 处理当前队列，空闲 5 秒后退出
.\render_video.ps1

# 不推上传队列
.\render_video.ps1 -noUpload

# 关闭 ffmpeg 进度行
.\render_video.ps1 -noProgress
```

`-shutdown` 会在队列处理完（通常配合不带 `-waitForNewTask` 使用）后执行 `shutdown.exe -f -s -t 60`。

## 上传端

```powershell
.\upload_video.ps1 -ValidateOnly
.\upload_video.ps1
```

上传端是常驻进程，从 `biliup:upload-list` 阻塞取任务。

## 加入渲染队列

把视频文件拖到 `append_render_redis.bat`，或者在 PowerShell 中：

```powershell
.\enqueue_render.ps1 'D:\record\a.mkv'
.\enqueue_render.ps1 'D:\record\a.mkv', 'D:\record\b.mkv' -DryRun
```

`bvid.txt` 放在本目录，内容为目标 BVID，例如：

```text
BV1xxxxxxxxx
```

拖拽脚本只是调用 `enqueue_render.ps1`，Redis 地址来自 `render.config.psd1`，不再需要 `REDIS_ADDRESS` 环境变量。

## RenderVideo 模块

模块可以单独导入，用于编码或快速拆分：

```powershell
Import-Module .\RenderVideo\RenderVideo.psd1

# 编码
Invoke-VideoRender -InputPath .\a.mkv -OutputPath .\out\a.mp4 -FastStart

# 按 10:00 / 20:00 拆分
Split-Video -InputPath .\a.mkv -TimePoint 10:00, 20:00

# 只输出 10:00-20:00（不输出开头和结尾）
Split-Video -InputPath .\a.mkv -TimePoint 10:00, 20:00 -OnlyInner

# 检查环境
Test-RenderEnvironment | Format-List
```

默认显示 ffmpeg 风格进度；`-NoProgress` 关闭。完整参数见 [`RenderVideo/README.md`](RenderVideo/README.md)。

## Redis 键

| 键 | 用途 |
| --- | --- |
| `biliup:render-list` | 待渲染任务 |
| `biliup:processing:rendering` | 当前渲染任务 |
| `biliup:upload-list` | 待上传任务 |
| `biliup:processing:uploading` | 当前上传任务 |
| `biliup:render-failed` | 渲染失败任务 |
| `biliup:upload-failed` | 上传失败任务 |

## 常见问题

- **找不到 ffmpeg / NVENC**：运行 `Test-RenderEnvironment`；确认 ffmpeg 带 `h264_nvenc`，并且驱动支持 NVENC。
- **Redis 连不上**：先运行 `redis-cli -h <host> PING`。
- **脚本无法执行**：设置执行策略，例如 `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`。
- **中文乱码**：`.ps1/.psm1/.psd1` 使用 UTF-8 with BOM；`.bat` 使用 ASCII/CRLF。
- **拆分时间不准**：`Split-Video` 使用 `-c copy`，只能按关键帧切；需要精确切点请重新编码。

更多设计说明见 [`../docs/architecture.md`](../docs/architecture.md) 和 [`../docs/render-video-module.md`](../docs/render-video-module.md)。
