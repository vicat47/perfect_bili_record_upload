@{
    # 复制本文件为 render.config.psd1 后修改；render.config.psd1 已被 .gitignore 忽略。
    # Webhook / Node-RED 通知地址（完整 URL）
    NotifyUrl    = 'https://your-nodered-domain.com/hooks/wechat/message'
    WechatTarget = 'your_wechat_target_id'

    # basic / bearer / none
    Auth         = @{
        Type     = 'basic'
        Username = 'your_username'
        Password = 'your_password_placeholder'
    }

    # Redis
    RedisHost    = 'your.redis.host'

    # OBS 录制文件目录；队列里的相对 filename 会拼接在这里
    InputPath    = 'X:\path\to\obs\recordings'

    # 编码输出目录
    OutputPath   = 'X:\path\to\output'

    # 可选：ffmpeg 日志目录；留空则不写日志
    LogDirectory = 'X:\path\to\output\logs'

    # RenderVideo 模块参数；Width/Height 设为 0 表示保持源分辨率
    Render       = @{
        VideoCodec   = 'h264_nvenc'
        Preset       = 'p5'
        Cq           = 19
        Width        = 2844
        Height       = 1600
        VideoBitrate = '20000k'
        MaxBitrate   = '30000k'
        BufferSize   = '30000k'
        AudioCodec   = 'aac'
        AudioBitrate = '320k'
        FastStart    = $true
    }
}
