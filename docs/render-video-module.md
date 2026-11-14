# RenderVideo 模块

`win_scripts/RenderVideo` 是从原 `render_video.ps1` 中抽出的纯编码/拆分模块。
它只调用 ffmpeg，不依赖 Redis、微信、上传队列，也不读取部署配置。

## 文件

```text
win_scripts/RenderVideo/
├─ RenderVideo.psd1   # 模块清单
├─ RenderVideo.psm1   # 实现
└─ README.md          # 完整参数和示例
```

## 公开函数

| 函数 | 作用 |
| --- | --- |
| `Invoke-VideoRender` | 编码单个视频，支持 NVENC / libx264 / copy |
| `Split-Video` | 用 `-c copy` 按多个时间点快速拆分 |
| `Test-RenderEnvironment` | 检查 ffmpeg、ffprobe、NVENC、libx264 |
| `Get-VideoInfo` | 用 ffprobe 读取媒体信息 |

## 设计决定

### 只做编码/拆分

模块不引用 Redis、微信、上传脚本，也不读取 `render.config.psd1`。
这样可以在任何 PowerShell 会话里单独使用，也方便以后换队列/通知实现。

### 参数数组调用 ffmpeg

不再拼一整个命令字符串，而是：

```powershell
& $ffmpeg @ffmpegArgArray
```

路径带空格、中文、括号都不会因为引号问题失败。

### 编码参数

- NVENC：`-rc:v vbr -cq:v <Cq>`
- libx264：`-crf <Cq>`
- `-Cq -1` 表示不用质量模式，改用 `-VideoBitrate`
- 原脚本里的 `-x264opts crf=12` 对 NVENC 无效，已移除

### 进度

两个函数都加 `-nostats -progress pipe:1`，解析 ffmpeg 的 key=value 进度块，再格式化成 ffmpeg 风格的单行：

```text
frame=    150 fps= 219.30 q= 23.0 size=     128kB time=00:00:04.99 bitrate=     209.7kbits/s speed=7.29x
```

默认开启，`-NoProgress` 关闭。进度写到 host，不进入日志，也不混入返回对象。

### 临时文件

`Invoke-VideoRender` 先写：

```text
xxx.mp4.part.mp4
```

成功后再替换目标文件。编码失败会删除 `.part`；如果只是最后移动失败，会保留 `.part` 方便恢复。

### 快速拆分

`Split-Video` 不循环调用 ffmpeg，而是一次调用 segment muxer：

```text
ffmpeg -i input -map 0 -c copy -f segment -segment_times t1,t2 -reset_timestamps 1 output_split_%d.ext
```

一次读取即可产出所有分段，速度接近磁盘复制。分段编号从 `-StartNumber`（默认 1）开始。

`-c copy` 只能在关键帧处切；如果两个时间点落在同一个 GOP 内，ffmpeg 可能少生成分段，函数会报错并保留已生成文件。

### 只输出内部区间

`Split-Video -OnlyInner`（别名 `-ExcludeEnds`）只输出 t1→t2、t2→t3 ...，不输出 0→t1 和 tN→end。
例如：

```powershell
Split-Video .\a.mkv 5 10 -OnlyInner
```

只输出 5 秒到 10 秒之间的内容。至少需要两个时间点；N 个时间点输出 N-1 段，编号从 `-StartNumber` 开始。

恰好两个时间点时走快速路径：直接用 `-ss <start> -i <input> -t <duration> -c copy` 只读中间段，不再处理 0→start 和 end→结尾。超过两个时间点仍先用临时目录生成全部分段，再只把内部区间移动到输出目录；成功后会删除临时目录，失败时保留并在错误信息中给出路径。

`-c copy` 仍然只能在关键帧处切，快速路径的实际切点可能比给定时间点早几百毫秒到几秒。

## 与原脚本相比修复的问题

| 原问题 | 现在 |
| --- | --- |
| 文件 GBK/ANSI 无 BOM，PowerShell 7 下中文路径乱码 | 脚本统一 UTF-8 with BOM |
| 上传队列推 `$rendering` 而不是 `$resp_json` | worker 使用明确的 payload JSON |
| 函数里的 `break` 会跳出 `Main` 的 `while` | 移除 `break`，失败走异常/失败队列 |
| 没有检查 ffmpeg 退出码 | `Invoke-VideoRender` 检查退出码并抛异常 |
| `-x264opts crf=12` 对 `h264_nvenc` 无效 | 改为 `-Cq` 映射到 `-cq` / `-crf` |
| 没有 `-y` / `-n`，输出已存在会卡住 | 输出先写 `.part`，默认不覆盖，`-Overwrite` 显式覆盖 |
| 相对文件名依赖当前工作目录 | worker 用配置的 `InputPath` 解析，支持绝对路径 |
| 通知失败会阻断后续 Redis 清理/上传 | 通知由 `Send-PipelineNotification` 捕获异常，不影响主流程 |
| 渲染失败后任务丢失 | 失败任务推入 `biliup:render-failed` |
| 没有实时进度 | 默认显示 ffmpeg 风格进度，`-NoProgress` 关闭 |

## 在 worker 中使用

`render_video.ps1` 已经在使用这个模块：

```powershell
Import-Module (Join-Path $PSScriptRoot 'RenderVideo\RenderVideo.psd1') -Force

$result = Invoke-VideoRender `
    -InputPath $inputPath `
    -OutputPath $outputPath `
    -VideoCodec h264_nvenc -Preset p5 -Cq 19 `
    -VideoBitrate 20000k -MaxBitrate 30000k -BufferSize 30000k `
    -Width 2844 -Height 1600 `
    -AudioCodec aac -AudioBitrate 320k `
    -FastStart -Overwrite
```

完整参数见 [`../win_scripts/RenderVideo/README.md`](../win_scripts/RenderVideo/README.md)。

## 配合上传队列

`RenderVideo` 本身仍然不访问 Redis。入队由 `PerfectBili.Common` 里的 `Add-UploadQueue` 负责，推荐用管道接在拆分/渲染后面：

```powershell
Import-Module .\RenderVideo\RenderVideo.psd1
Import-Module .\PerfectBili.Common\PerfectBili.Common.psd1

Split-Video -InputPath .\a.mkv -TimePoint 10:00, 20:00 |
    Add-UploadQueue -Bvid BV1xxxxxxxxx -RedisHost 192.168.31.40
```

`Add-UploadQueue` 接受 `Split-Video` / `Invoke-VideoRender` 的返回对象、`FileInfo` 或路径字符串；每个文件生成一条 JSON 并按顺序 `RPUSH` 到 `biliup:render-list`（默认队列）。`filename` 默认是文件名（`-FileNameStyle Leaf`），因为 NAS 上的 Node-RED 上传流程只接受文件名，不接受 `X:\...` 绝对路径；产物需要放在它的 `SOURCE_DIR` 下。`-WhatIf` 不连接 Redis，`-PassThru` 返回队列项，入队失败后可以只重试入队。

## 验证记录

- PowerShell `7.6.9` 和 Windows PowerShell `5.1.26100` 都能导入模块。
- 实际 NVENC 编码、`Split-Video` 拆分、进度显示均通过。
- `-NoProgress` 可关闭进度，日志中不包含进度行。
- 参数错误会抛异常并清理临时 `.part` 文件。
- 现有输出未加 `-Overwrite` 会直接报错。
- `Split-Video -OnlyInner` 在 `test.mkv` 上验证：5:00/10:00 输出 1 段（约 300 秒），5:00/10:00/15:00 输出 2 段；临时目录成功后清理。
- `-OnlyInner` 只传一个时间点会报错；关键帧不足时会报错并保留临时目录。
- Windows PowerShell `5.1.26100` 下 `-OnlyInner -DryRun` 通过。
- `-OnlyInner` 恰好两个时间点时走 `-ss`/`-t` 快速路径；`test.mkv` 5:00–10:00 输出约 301 秒，和 segment muxer 的 300 秒结果接近。
- 超过两个时间点时仍使用 segment muxer；`-DryRun` 命令中能看到 `-segment_times`。
- segment muxer 没有 `total_size` 时，进度显示 `size=N/A`，不再显示误导性的 `0kB`；快速路径显示实际大小。
- `Split-Video ... | Add-UploadQueue` 在 `test.mkv` 上生成 3 段并按 `_split_1`、`_split_2`、`_split_3` 顺序写入测试队列。
- `Add-UploadQueue -WhatIf` 不连接 Redis；`-PassThru` 返回计划 JSON、`QueueLength` 和 `Queued`。
- PowerShell `7.6.9` 和 `5.1.26100` 下中文文件名入队正常，Redis 中的 JSON 为有效 UTF-8。
- `-FileNameStyle` 默认 `Leaf` 输出文件名，`FullName` 输出绝对路径；两种模式都包含 `path` 字段。
- `-Metadata` 可以附加字段；覆盖 `filename` / `bvid` 会直接报错。
