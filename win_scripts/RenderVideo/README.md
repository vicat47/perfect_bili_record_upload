# RenderVideo

一个只负责「用 ffmpeg 编码 / 拆分视频」的 PowerShell 模块。
不包含 Redis、微信通知、上传队列，也不依赖原 `render_video.ps1` 里的任何配置。

模块函数：

- `Invoke-VideoRender`：编码渲染
- `Split-Video`：`-c copy` 快速拆分
- `Test-RenderEnvironment`：检查 ffmpeg / ffprobe / NVENC
- `Get-VideoInfo`：读取媒体信息

> 模块设计、原脚本问题清单和迁移说明见 [`docs\render-video-module.md`](../../docs/render-video-module.md)。

## 文件结构

```text
win_scripts/
  RenderVideo/
    RenderVideo.psd1   # 模块清单
    RenderVideo.psm1   # 实现
    README.md          # 本文档
  render_video.ps1     # 渲染 worker，已集成此模块
  render.config.example.psd1
```

## 导入模块

### 方式一：直接按路径导入

在 `win_scripts` 目录：

```powershell
Import-Module .\RenderVideo\RenderVideo.psd1
```

在仓库根目录：

```powershell
Import-Module .\win_scripts\RenderVideo\RenderVideo.psd1
```

### 方式二：把 win_scripts 加进 PSModulePath

```powershell
$env:PSModulePath = "$PWD\win_scripts;$env:PSModulePath"
Import-Module RenderVideo
```

### 方式三：永久安装

PowerShell 7：

```powershell
Copy-Item .\win_scripts\RenderVideo "$HOME\Documents\PowerShell\Modules\RenderVideo" -Recurse
```

Windows PowerShell 5.1：

```powershell
Copy-Item .\win_scripts\RenderVideo "$HOME\Documents\WindowsPowerShell\Modules\RenderVideo" -Recurse
```

之后任何 PowerShell 会话都可以直接：

```powershell
Import-Module RenderVideo
```

## 快速开始

```powershell
Import-Module .\win_scripts\RenderVideo\RenderVideo.psd1

Invoke-VideoRender `
    -InputPath '.\recordings\2026-10-31_11-42-08.mkv' `
    -OutputPath '.\output\2026-10-31_11-42-08.mp4'
```

默认参数大致等价于原来的渲染命令：

- `h264_nvenc`
- `-preset p5`
- `-cq 19`
- `-b:v 20000k`
- `-maxrate:v 30000k`
- `-bufsize:v 30000k`
- `aac 320k`
- `yuv420p`

## 常用示例

### 固定 2844x1600，开启 faststart

```powershell
Invoke-VideoRender `
    -InputPath '.\2026-10-31_11-42-08.mkv' `
    -OutputPath '.\输出\2026-10-31_11-42-08.mp4' `
    -VideoCodec h264_nvenc -Preset p5 -Cq 19 `
    -VideoBitrate 20000k -MaxBitrate 30000k -BufferSize 30000k `
    -Width 2844 -Height 1600 `
    -FastStart
```

### 软件编码 libx264

```powershell
Invoke-VideoRender `
    -InputPath '.\a.mkv' `
    -OutputPath '.\out\a.mp4' `
    -VideoCodec libx264 -Preset veryslow -Cq 18
```

### 只换封装，不重新编码

```powershell
Invoke-VideoRender `
    -InputPath '.\a.mkv' `
    -OutputPath '.\out\a.mp4' `
    -VideoCodec copy -AudioCodec copy
```

### 先看命令，不实际编码

```powershell
Invoke-VideoRender `
    -InputPath '.\a.mkv' `
    -OutputPath '.\out\a.mp4' `
    -DryRun
```

### 覆盖已有文件

```powershell
Invoke-VideoRender `
    -InputPath '.\a.mkv' `
    -OutputPath '.\out\a.mp4' `
    -Overwrite
```

### 批量

```powershell
$outputRoot = '.\output'

Get-ChildItem '.\recordings' -Filter '*.mkv' | ForEach-Object {
    $output = Join-Path $outputRoot ([IO.Path]::GetFileNameWithoutExtension($_.Name) + '.mp4')
    try {
        $result = Invoke-VideoRender -InputPath $_.FullName -OutputPath $output -Overwrite -FastStart
        Write-Host "完成: $($result.OutputPath) ($([math]::Round($result.Elapsed.TotalMinutes, 2)) 分钟)"
    }
    catch {
        Write-Error "失败: $($_.Exception.Message)"
    }
}
```

## 进度显示

`Invoke-VideoRender` 和 `Split-Video` 默认都会显示 ffmpeg 风格的实时进度：

```text
frame=    150 fps= 219.30 q= 23.0 size=     128kB time=00:00:04.99 bitrate=     209.7kbits/s speed=7.29x
```

进度写到 host，不会混进函数返回的对象。需要关闭时加：

```powershell
Invoke-VideoRender ... -NoProgress
Split-Video ... -NoProgress
```

内部使用 `ffmpeg -progress pipe:1 -nostats`，再解析 `frame/fps/q/size/time/bitrate/speed`；`-Verbose` 仍用于显示 ffmpeg 的详细日志，通常配合 `-LogLevel info`。

## 检查环境

```powershell
Test-RenderEnvironment | Format-List
```

会检查：

- `ffmpeg` 路径和版本
- `ffprobe` 是否存在
- ffmpeg 是否编译了 `h264_nvenc`、`hevc_nvenc`、`libx264`

注意：`-encoders` 里有 `h264_nvenc` 只表示 ffmpeg 支持它，不代表当前机器 GPU/驱动一定可用；真正编码时如果 NVENC 不可用，会抛出 ffmpeg 的错误。

## 读取媒体信息

```powershell
Get-VideoInfo -InputPath '.\a.mkv' | Format-List

# 查看音视频流
$info = Get-VideoInfo -InputPath '.\a.mkv'
$info.VideoStreams | Format-Table index, codec_name, width, height, r_frame_rate
$info.AudioStreams | Format-Table index, codec_name, channels, bit_rate
```

## 快速拆分视频（-c copy）

用 ffmpeg 的 segment muxer 按多个时间点拆分，不重新编码：

```powershell
# 输入 a.mkv，按 10 分钟、20 分钟切开
Split-Video -InputPath .\a.mkv -TimePoint 00:10:00,00:20:00
```

默认输出到当前目录：

```text
a_split_1.mkv    # 0 -> 10:00
a_split_2.mkv    # 10:00 -> 20:00
a_split_3.mkv    # 20:00 -> end
```

也支持直接写多个参数：

```powershell
Split-Video .\a.mkv 10:00 20:00
```

指定输出目录、强制 mp4、覆盖已有文件：

```powershell
Split-Video .\a.mkv 600,1200 `
    -OutputDirectory .\out `
    -OutputExtension .mp4 `
    -Overwrite
```

时间点格式：

- `600`：秒
- `10:00`：分:秒
- `00:10:00`：时:分:秒
- `00:10:00.500`：带毫秒

0 和结尾不需要传；内部时间点会自动排序、去重。传 0 或重复时间点会被忽略并给出警告；等于/略晚于结尾的时间点会被忽略，明显超过结尾会报错。

### Split-Video 参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-InputPath` | 必填 | 输入文件 |
| `-TimePoint` | 必填 | 一个或多个内部时间点 |
| `-OutputDirectory` | 当前目录 | 输出目录 |
| `-OutputName` | 输入文件名 | 输出文件名前缀，自动去掉扩展名 |
| `-OutputExtension` | 输入扩展名 | 输出扩展名，例如 `.mp4` |
| `-StartNumber` | `1` | 第一段的编号 |
| `-Overwrite` | 关 | 输出已存在时允许覆盖 |
| `-NoProgress` | 关 | 关闭实时进度 |
| `-LogLevel` | `warning` | ffmpeg 日志级别 |
| `-LogPath` | 空 | 把 ffmpeg 输出写到文件 |
| `-DryRun` | 关 | 只构建命令并返回 |
| `-WhatIf` | - | 标准 `-WhatIf` |

### 注意

- `-c copy` 只能在关键帧处切，实际切点可能比给定时间点早或晚；如果两个时间点落在同一个 GOP 内，ffmpeg 可能少生成分段，函数会报错并保留已生成的文件。需要精确切点请重新编码。
- 默认保留输入容器的扩展名。强制 `-OutputExtension .mp4` 时，如果源码流/字幕等 MP4 不支持，ffmpeg 会报错。
- 使用 `-map 0` 保留所有流（视频、音频、字幕等）。
- 之前拆分留下的 `_split_n` 文件不会自动删除；重新拆分时注意 `-Overwrite` 和编号。
- 拆分失败时，已经生成的 segment 文件可能会保留，重跑时用 `-Overwrite`。

## Invoke-VideoRender 主要参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-InputPath` | 必填 | 输入文件 |
| `-OutputPath` | 必填 | 输出文件，必须带扩展名 |
| `-VideoCodec` | `h264_nvenc` | `h264_nvenc` / `hevc_nvenc` / `libx264` / `copy` |
| `-Preset` | `p5`（NVENC）或 `medium`（x264） | 编码预设 |
| `-Cq` | `19` | NVENC 的 `-cq`，x264 的 `-crf`；设为 `-1` 表示改用 `-VideoBitrate` |
| `-VideoBitrate` | `20000k` | 目标视频码率 |
| `-MaxBitrate` | `30000k` | 最大码率，空字符串表示不限制 |
| `-BufferSize` | `30000k` | VBV buffer，空字符串表示不设置 |
| `-VideoProfile` | `main` | H.264/H.265 profile |
| `-PixelFormat` | `yuv420p` | 像素格式 |
| `-Width` / `-Height` | `0` | 输出尺寸；只给一个时会按比例缩放，两个都给则强制该尺寸 |
| `-AudioCodec` | `aac` | `aac` / `libopus` / `copy` / `none` |
| `-AudioBitrate` | `320k` | 音频码率 |
| `-AudioTrack` | `0` | 默认只保留第一条音轨 |
| `-AllAudio` | 关 | 保留所有音轨 |
| `-NoAudio` | 关 | 不输出音频 |
| `-FastStart` | 关 | MP4/MOV 加 `-movflags +faststart` |
| `-Overwrite` | 关 | 输出已存在时允许覆盖；不加会直接报错 |
| `-LogLevel` | `warning` | ffmpeg 日志级别 |
| `-LogPath` | 空 | 把 ffmpeg 输出写到文件 |
| `-NoProgress` | 关 | 关闭实时进度 |
| `-ExtraFFmpegArgs` | 空 | 追加任意 ffmpeg 参数 |
| `-DryRun` | 关 | 只构建命令并返回，不执行 |
| `-WhatIf` | - | 标准 PowerShell `-WhatIf` 支持 |

## 行为说明

- 不会覆盖输入文件。
- 输出先写到同目录的 `xxx.mp4.part.mp4`，成功后才替换 `xxx.mp4`；编码失败会删除 `.part`，如果只是最后移动失败会保留 `.part` 方便恢复。
- 输出已存在且没有 `-Overwrite` 时，会在启动 ffmpeg 前直接报错，不会卡在 `Overwrite? [y/N]`。
- 编码失败会抛出异常，异常里包含 ffmpeg 退出码和最后 30 行日志。
- 默认显示 ffmpeg 风格进度；`-NoProgress` 关闭。`-Verbose` 用于显示 ffmpeg 的详细日志。
- 成功时返回一个对象，包含 `OutputPath`、`Elapsed`、`OutputSizeBytes`、`CommandLine` 等字段。
- 模块本身不读写 Redis，不发微信，不做上传。

## 在仓库中的使用

`win_scripts/render_video.ps1` 已经集成此模块，并使用 `win_scripts/render.config.example.psd1` 作为配置模板。
worker 的运行方式和配置字段见 [`../README.md`](../README.md)。
