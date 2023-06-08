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
    $result = redis-cli -h 192.168.1.2 BLPOP biliup:upload-list 0
    if ($result -eq "") {
        Write-Output "No value found in biliup:upload-list"
        continue
    }
    $json = ConvertFrom-Json $result[1]
    # 必须替换为这个，要不然 redis-cli 不认识。
    redis-cli -h 192.168.1.2 SET biliup:processing:uploading $result[1].Replace('"', '\"')
    biliup append -l qn --limit 6 --vid $json.bvid $json.filename
    Send-WechatMessage "$($json.filename) 上传完毕"
    # 后续使用
    # $rendering = redis-cli -h 192.168.1.2 GET biliup:processing:rendering
    # if ($result -eq "") {
    #     Write-Output "No value found in biliup:processing:rendering"
    #     continue
    # }
    # $rendering_json = ConvertFrom-Json $rendering[1]
    redis-cli -h 192.168.1.2 DEL biliup:processing:rendering
}