# 完美的 bilibili 录制方案

## why

一条龙服务，还可以多机操作，爽爆！

## what

依赖如下组件
- redis
- ffmpeg
- obs
- smb

```bash
perfect_bili_record_upload
├─ README.md                        # README 文件
├─ obs_scripts                      # OBS 脚本文件
│    ├─ README.md                   ## 注意事项
│    ├─ handle_stop.py              ## 监听录制停止事件，脚本的主要内容
│    └─ load_config.py              ## 读取配置文件（测试）
└─ win_scripts                      # windows 用的脚本
       ├─ append_render_redis.bat   ## 将文件加入渲染列表
       ├─ render_video.ps1          ## 渲染视频
       └─ upload_video.ps1          ## 上传视频
```

### 图解

![流程图](./README.assets/flow.drawio.svg)

## how

1. 拖拽视频到 `append_render_redis.bat`。
2. 使用 `OBS` 加载脚本：`handle_stop.py`
3. 打开 `render_video.ps1` 执行渲染视频命令。
4. 打开 `upload_video.ps1` 等待视频上传。
5. 打开 `bilibili`，欣赏你上传的影片。


# 依赖项目

1. [【github】tporadowski | redis](https://github.com/tporadowski/redis)
2. [【github】biliup | biliup-rs](https://github.com/biliup/biliup-rs)

# 参考文献

1. [【bilibili】请叫我雯子小姐的小爷 | 69行代码！！！自己动手写一个OBS脚本插件，录制/直播任何你想展示的动态数据](https://www.bilibili.com/video/BV18t4y1S7by)
2. [【github】upgradeQ | OBS Studio Python Scripting Cheatsheet](https://github.com/upgradeQ/OBS-Studio-Python-Scripting-Cheatsheet-obspython-Examples-of-API)