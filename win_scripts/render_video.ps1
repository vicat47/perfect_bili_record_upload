param(
    [Parameter()]
    [switch]$waitForNewTask,
    [Parameter()]
    [switch]$shutdown,
    [Parameter()]
    [switch]$noUpload
)

class AuthParam {
    [string]$Type
    [string]$Username
    [string]$Password
}

class RenderProperties {
    [string]$NotifyUrl
    [string]$WechatTarget
    [string]$RedisHost
    [string]$OutputPath
    [AuthParam]$Auth
}

# 统一配置变量 (脚本作用域)
$script:Config = [RenderProperties]@{
    NotifyUrl = "https://your-nodered-domain.com/hooks/wechat/message"  # 替换为通知目标URL
    WechatTarget = "your_wechat_target_id"           # 替换为你的微信目标ID
    RedisHost = "your.redis.host"                   # 替换为你的Redis主机地址
    OutputPath = "X:\path\to\output\"               # 替换为你的输出路径
    Auth = [AuthParam]@{
        Type = "basic"
        Username = "your_username"                  # 替换为你的用户名
        Password = "your_password_placeholder"      # 替换为你的密码
    }
}

function Send-WechatMessage {
    param (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$Content,
        [Parameter(Mandatory=$false)]
        [string]$NotifyUrl,
        [Parameter(Mandatory=$false)]
        [string]$SendTarget,
        [Parameter(Mandatory=$false)]
        [AuthParam]$Auth
    )
    
    $uri = "$($NotifyUrl)"
    # Basic Auth 认证信息
    if (-not $Auth) {
        $Auth = [AuthParam]@{
            Type = "basic"
            Username = "your_username"              # 替换为你的用户名
            Password = "your_password_placeholder"  # 替换为你的密码
        }
    }
    $BODY = @{
        target = "$($SendTarget)"
        content = $Content
    }
    if ($Auth.Type -eq "basic") {
        $user = $Auth.Username
        $pass = $Auth.Password
        $secpasswd = ConvertTo-SecureString $pass -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($user, $secpasswd)
        Invoke-WebRequest -Uri $uri -Credential $credential -Method Post -ContentType "application/json; charset=utf-8" -Body ($BODY | ConvertTo-Json)
    } elseif ($Auth.Type -eq "bearer") {
        Invoke-WebRequest -Uri $uri -Headers @{ Authorization = "Bearer $($Auth.Password)" } -Method Post -ContentType "application/json; charset=utf-8" -Body ($BODY | ConvertTo-Json)
    } else {
        Invoke-WebRequest -Uri $uri -Method Post -ContentType "application/json; charset=utf-8" -Body ($BODY | ConvertTo-Json)
    }
}

function Main {
    while ($true) {
        if ($waitForNewTask.IsPresent) {
            $result = redis-cli -h $script:Config.RedisHost BLPOP biliup:render-list 0
        } else {
            $result = redis-cli -h $script:Config.RedisHost BLPOP biliup:render-list 5
        }

        Write-Output "$($result)"
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
        redis-cli -h $script:Config.RedisHost SET biliup:processing:rendering $resp_json.Replace('"', '\"')
        ffmpeg -i $json.filename -c:v h264_nvenc -profile:v main -b:v 20000k -profile:v main -s 2844x1600 -c:a aac -b:a 320k -x264opts crf=12 -maxrate:v 30000k -bufsize 30000k -pix_fmt yuv420p "$($script:Config.OutputPath)$($new_value)"
        Send-WechatMessage -Content "$($json.filename) 渲染完毕" -BaseUrl $script:Config.NotifyUrl -SendTarget $script:Config.WechatTarget -Auth $script:Config.Auth
        $rendering = redis-cli -h $script:Config.RedisHost GET biliup:processing:rendering
        if ($rendering -eq "") {
            Write-Output "No value found in biliup:processing:rendering"
            break
        }
        redis-cli -h $script:Config.RedisHost DEL biliup:processing:rendering
        if (!$noUpload.IsPresent) {
            redis-cli -h $script:Config.RedisHost RPUSH biliup:upload-list $rendering.Replace('"', '\"')
        }
    }

    if ($shutdown.IsPresent) {
        shutdown -f -s -t 60
    }
}

Main
# Send-WechatMessage -Content "test渲染完毕" -BaseUrl $script:Config.NotifyUrl -SendTarget $script:Config.WechatTarget -Auth $script:Config.Auth