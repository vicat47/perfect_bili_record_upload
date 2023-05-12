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
    $result = redis-cli -h 192.168.1.2 BLPOP render-list 5
    if ($result -eq "") {
        Write-Output "No value found in render-list"
        break
    }
    $value = $result[1]
    $name = $value.Split(".")[0]
    $new_value = "$name.mp4"
    ffmpeg -i $value -c:v libx264 -profile:v main -b:v 20000k -profile:v main -preset veryslow -s 2844x1600 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 30000k -bufsize 30000k -pix_fmt yuv420p "R:\OBS\ï¿½ï¿½ï¿½\$($new_value)"
    Send-WechatMessage "$($value)ï¿½ï¿½È¾ï¿½ï¿½ï¿?"
    redis-cli -h 192.168.1.2 RPUSH upload-list $new_value
}

# shutdown -f -s -t 0