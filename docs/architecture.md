# 架构与数据流

## 总览

```mermaid
flowchart LR
    OBS[OBS 录制停止<br/>obs_scripts/handle_stop.py] -->|RPUSH| RL[biliup:render-list]
    ENQ[append_render_redis.bat<br/>enqueue_render.ps1] -->|RPUSH| RL
    PIPE[Split-Video | Add-UploadQueue] -->|RPUSH| RL
    RL -->|BLPOP| DF[Node-RED biliup 直接 v2]
    DF -->|biliup append| BILI[Bilibili]
    DF -.失败.-> UF[biliup:upload-failed]
    OLD[旧 biliup:upload-list flow] -.已禁用.-> BILI
```

## 组件

| 组件 | 作用 |
| --- | --- |
| `obs_scripts/handle_stop.py` | OBS 录制停止时把最新录制文件推入 `biliup:render-list` |
| `win_scripts/enqueue_render.ps1` | 手动/拖拽把文件推入 `biliup:render-list` |
| `win_scripts/append_render_redis.bat` | 拖拽入口，调用 `enqueue_render.ps1` |
| `win_scripts/render_video.ps1` | 历史渲染 worker；当前部署已不使用 |
| `win_scripts/upload_video.ps1` | 历史上传 worker；旧 `biliup:upload-list` flow 已禁用 |
| `win_scripts/RenderVideo/` | 纯编码/拆分模块，不依赖 Redis、通知或上传 |
| `win_scripts/PerfectBili.Common/` | 公共日志、微信通知、Redis CLI 封装、`Add-UploadQueue` 入队 |
| Node-RED `biliup 直接 v2` | 从 `biliup:render-list` 取任务，直接 `biliup append` 上传 source/拆分文件 |

## 队列与状态键

| 键 | 类型 | 说明 |
| --- | --- | --- |
| `biliup:render-list` | List | 待直接上传任务，元素为 JSON：`{"filename":"...","bvid":"BV..."}` |
| `biliup:processing:rendering` | String | 历史渲染任务状态（保留） |
| `biliup:upload-list` | List | 旧渲染输出队列，已禁用 |
| `biliup:processing:uploading` | String | 当前直接上传任务 |
| `biliup:render-failed` | List | 历史渲染失败任务（保留） |
| `biliup:upload-failed` | List | 上传失败的任务，保留原始 JSON |
| `obs:record` | String | OBS 录制状态（`stop` / `paused`） |
| `obs:status` | String | OBS 脚本加载状态 |

失败列表是新增的，便于排查和手动重试；不会自动重试，避免坏任务无限循环。

`Invoke-RedisCli` 统一使用 UTF-8 读写 Redis，中文文件名和路径在 Windows PowerShell 5.1 下也不会乱码。

## 当前直接上传流程

1. OBS 停止、`enqueue_render.ps1` 或 `Split-Video | Add-UploadQueue` 把任务推入 `biliup:render-list`。
2. Node-RED `biliup 直接 v2` 从 `biliup:render-list` `BLPOP` 取任务。
3. 在 `/mnt/record/OBS/source` 解析文件；如果文件名是 `_split_n`，直接上传该分段；如果是原始文件名，则按顺序寻找 `_split_1..N`。
4. 写入 `biliup:processing:uploading`，执行 `biliup append`。
5. 成功后清理状态；失败时推入 `biliup:upload-failed`。

旧的 `biliup:upload-list` flow 已禁用，不再使用 `/mnt/record/OBS/输出`。

## 历史渲染流程

1. `render_video.ps1` 从 `biliup:render-list` `BLPOP` 取任务。
2. 写入 `biliup:processing:rendering`。
3. 根据 `render.config.psd1` 的 `InputPath` 解析输入文件，调用 `Invoke-VideoRender`。
4. 成功后：
   - 通知微信
   - 删除 `biliup:processing:rendering`
   - 推入 `biliup:upload-list`（除非 `-noUpload`）
5. 失败时：
   - 通知微信
   - 删除 `biliup:processing:rendering`
   - 推入 `biliup:render-failed`

`-waitForNewTask` 使用 `BLPOP ... 0` 常驻等待；不加时使用 5 秒超时，队列空闲后退出，可配合 `-shutdown`。

## 历史上传流程

1. `upload_video.ps1` 从 `biliup:upload-list` `BLPOP` 取任务。
2. 写入 `biliup:processing:uploading`。
3. 根据 `upload.config.psd1` 的 `OutputPath` 解析文件，执行：
   `biliup append <BiliupArgs> --vid <bvid> <file>`
4. 成功后通知微信并清理状态。
5. 失败时通知微信、清理状态，并推入 `biliup:upload-failed`。

## 配置

- `win_scripts/render.config.psd1`：Redis、输入/输出目录、通知、编码参数。
- `win_scripts/upload.config.psd1`：Redis、输出目录、通知、biliup 参数。
- 两个真实配置文件都被 `.gitignore` 忽略；仓库只提交 `*.example.psd1`。
- 通知地址是完整 URL，支持 `basic` / `bearer` / `none`。
- 通知 JSON 统一为 `{ "target": "...", "content": "..." }`；旧上传脚本的 `para` 格式已不再使用。

## 编码与拆分

- 编码由 `RenderVideo` 模块完成，默认 `h264_nvenc`、`-cq 19`、20M 目标码率、30M 上限。
- 进度使用 `ffmpeg -progress pipe:1` 解析后显示，默认开启，`-NoProgress` 关闭。
- 快速拆分使用 `Split-Video`，内部是一次 `-f segment -segment_times ... -c copy` 调用。
- `-c copy` 只能在关键帧处切，实际切点可能有偏差；同一 GOP 内的多个时间点可能被合并，函数会报错并保留已生成文件。
- 拆分/渲染产物可以通过 `PerfectBili.Common` 的 `Add-UploadQueue` 管道入队：
  `Split-Video ... | Add-UploadQueue -Bvid BV... -RedisHost ...`。每个分段一条 JSON，默认只包含 `filename` 和 `bvid`。
- NAS 上的 Node-RED 上传流程只接受文件名（不能是 `X:\...`），并按 `SOURCE_DIR` 解析；所以拆分产物应输出到 `/mnt/record/OBS/source`（Windows 侧 `X:\record\OBS\source`）。

## 部署建议

- 代码放在本仓库；实际配置放在部署机的 `win_scripts/*.config.psd1`。
- 渲染 worker 和上传 worker 可以分别运行在不同机器，只要连同一个 Redis。
- 建议用计划任务/开机启动让 `render_video.ps1 -waitForNewTask` 和 `upload_video.ps1` 常驻。
- 日志目录、输出目录需要提前规划磁盘空间。
