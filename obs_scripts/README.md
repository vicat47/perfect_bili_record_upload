OBS 脚本仅支持 Python 3.6+（OBS 内置 Python）。

需要安装依赖：

```bash
pip install redis
```

`handle_stop.py` 会在录制停止时：

- 从 OBS 录制目录挑选最新的视频文件（`.mkv` / `.mp4` / `.flv` / `.ts` / `.mov`）
- 推入 Redis 的 `biliup:render-list`

OBS 脚本属性里的 Redis host / port / database 需要和 `win_scripts/render.config.psd1` 指向同一个 Redis。
