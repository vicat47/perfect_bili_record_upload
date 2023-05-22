function Send-WechatMessage {
    param (
        $Content
    )
    $BODY = @{
        para = @{
            id = (([DateTime]::Now.ToUniversalTime().Ticks - 621355968000000000)/10000).tostring().Substring(0,13)
            type = 555
            roomid = "null"
            wxid = "wxid_xxxxxxxxxxxxxx"
            content = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::UTF8.GetBytes($Content))
            nickname = "null"
            ext = "null"
        }
    }
    Invoke-WebRequest -Uri "http://webhook_address" -Method Post -ContentType "application/json; charset=utf-8" -Body ($BODY | ConvertTo-Json)
}

while ($true) {
    $result = redis-cli -h $REDIS_ADDRESS BLPOP render-list 5
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
    $resp_json = $resp_json.Replace('"', '\"')
    ffmpeg -i $json.filename -c:v libx264 -profile:v main -b:v 20000k -profile:v main -preset veryslow -s 2844x1600 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 30000k -bufsize 30000k -pix_fmt yuv420p "R:\OBS\输出\$($new_value)"
    Send-WechatMessage "$($json.filename) 渲染完毕"
    Write-Output $resp_json
    redis-cli -h $REDIS_ADDRESS RPUSH upload-list $resp_json
}

# shutdown -f -s -t 0