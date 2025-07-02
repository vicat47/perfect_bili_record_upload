param(
    # 参数：是否等待新任务1
    [Parameter()]
    [switch]$waitForNewTask,
    # 参数：所有任务结束后是否关机
    [Parameter()]
    [switch]$shutdown,
    # 参数：是否不进入上传队列
    [Parameter()]
    [switch]$noUpload
)

function Send-WechatMessage {
    param (
        $Content
    )
    # 原始报文
    # $BODY = @{
    #     para = @{
    #         id = (([DateTime]::Now.ToUniversalTime().Ticks - 621355968000000000)/10000).tostring().Substring(0,13)
    #         type = 555
    #         roomid = "null"
    #         目标用户
    #         wxid = "xxxxxxxxxxxxxx"
    #         content = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::UTF8.GetBytes($Content))
    #         nickname = "null"
    #         ext = "null"
    #     }
    # }
    # 原始请求
    # Invoke-WebRequest -Uri "http://xxxxxxxxxxxxxxxxxxxxxxx" -Method Post -ContentType "application/json; charset=utf-8" -Body ($BODY | ConvertTo-Json)
    $BODY = @{
        target = "微信id"
        content = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::UTF8.GetBytes($Content))
    }
    # 这里是自定义的 webhook 用于简化上面的请求
    Invoke-WebRequest -Uri "https://xxxxxxxxxxxxxxxxxxxx" -Headers @{ Authorization = 'Bearer xxxxxxxxxxxxx' } -Method Post -ContentType "application/json; charset=utf-8" -Body ($BODY | ConvertTo-Json)
}

while ($true) {
    if ($waitForNewTask.IsPresent) {
        # redis 地址
        $result = redis-cli -h 192.168.31.15 BLPOP biliup:render-list 0
    } else {
        $result = redis-cli -h 192.168.31.15 BLPOP biliup:render-list 5
    }

    if ($result -eq "") {
        Write-Output "No value found in render-list"
        break
    }
    $json = ConvertFrom-Json $result[1]
    $name = $json.filename.Split(".")[0]
    $new_value = "$name.mp4"
    # json
    $resp = @{
        filename = $new_value
        bvid = $json.bvid
    }
    $resp_json = ConvertTo-Json -Compress -InputObject $resp
    # 必须替换为这个，要不然 redis-cli 不认识。
    redis-cli -h 192.168.31.15 SET biliup:processing:rendering $resp_json.Replace('"', '\"')
    # 通过 cpu 渲染视频
    # ffmpeg -i $json.filename -c:v libx264 -profile:v main -b:v 20000k -profile:v main -preset veryslow -s 2844x1600 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 30000k -bufsize 30000k -pix_fmt yuv420p "R:\OBS\输出\$($new_value)"
    # 通过显卡渲染视频，精度没有 cpu好，但是时间特别快
    # 输出到电脑挂载的硬盘上
    ffmpeg -i $json.filename -c:v h264_nvenc -profile:v main -b:v 20000k -profile:v main -s 2844x1600 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 30000k -bufsize 30000k -pix_fmt yuv420p "R:\OBS\输出\$($new_value)"
    Send-WechatMessage "$($json.filename) 渲染完毕"
    $rendering = redis-cli -h 192.168.31.15 GET biliup:processing:rendering
    if ($rendering -eq "") {
        Write-Output "No value found in biliup:processing:rendering"
        break
    }
    redis-cli -h 192.168.31.15 DEL biliup:processing:rendering
    if (!$noUpload.IsPresent) {
        redis-cli -h 192.168.31.15 RPUSH biliup:upload-list $rendering.Replace('"', '\"')
    }
}

if ($shutdown.IsPresent) {
    shutdown -f -s -t 60
}