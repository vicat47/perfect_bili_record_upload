@{
    # 复制本文件为 upload.config.psd1 后修改；upload.config.psd1 已被 .gitignore 忽略。
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

    # render_video.ps1 的输出目录；队列里的 filename 会拼接在这里
    OutputPath   = 'X:\path\to\output'

    # biliup 可执行文件；在 PATH 中时直接写 biliup
    BiliupPath   = 'biliup'

    # biliup append 的公共参数；不要在这里重复 --vid
    BiliupArgs   = @('-l', 'qn', '--limit', '6')
}
