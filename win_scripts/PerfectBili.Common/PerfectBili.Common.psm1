#Requires -Version 5.1

function Write-PipelineLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    process {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line = "[$timestamp] [$Level] $Message"
        switch ($Level) {
            'ERROR' { Write-Host $line -ForegroundColor Red }
            'WARN' { Write-Host $line -ForegroundColor Yellow }
            default { Write-Host $line }
        }
    }
}

function Send-WechatMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$NotifyUrl,

        [Parameter(Mandatory = $true)]
        [string]$SendTarget,

        [Parameter(Mandatory = $false)]
        $Auth
    )

    process {
        $body = @{
            target  = $SendTarget
            content = $Content
        }
        $json = $body | ConvertTo-Json -Compress
        $bodyBytes = [Text.Encoding]::UTF8.GetBytes($json)

        $request = @{
            Uri         = $NotifyUrl
            Method      = 'Post'
            ContentType = 'application/json; charset=utf-8'
            Body        = $bodyBytes
            TimeoutSec  = 15
        }

        if ($PSVersionTable.PSVersion.Major -lt 6) {
            $request.UseBasicParsing = $true
        }

        if ($Auth) {
            switch ($Auth.Type) {
                'basic' {
                    $pair = "$($Auth.Username):$($Auth.Password)"
                    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
                    $request.Headers = @{ Authorization = "Basic $token" }
                }
                'bearer' {
                    $request.Headers = @{ Authorization = "Bearer $($Auth.Password)" }
                }
            }
        }

        Invoke-WebRequest @request | Out-Null
    }
}

function Send-PipelineNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        $Config
    )

    try {
        Send-WechatMessage -Content $Content -NotifyUrl $Config.NotifyUrl -SendTarget $Config.WechatTarget -Auth $Config.Auth
    }
    catch {
        Write-PipelineLog -Level WARN -Message "Notification failed: $($_.Exception.Message)"
    }
}

function Invoke-RedisCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RedisHost,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [string]$InputValue,
        [string]$RedisCliPath = 'redis-cli'
    )

    if ($Arguments.Count -eq 0) {
        throw 'Redis command arguments are required.'
    }

    $command = Get-Command -Name $RedisCliPath -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "redis-cli not found: $RedisCliPath"
    }
    $redisCli = if (-not [string]::IsNullOrWhiteSpace($command.Source)) { $command.Source } else { $command.Name }

    if ($PSBoundParameters.ContainsKey('InputValue')) {
        $output = $InputValue | & $redisCli -h $RedisHost --raw -x @Arguments
    }
    else {
        $output = & $redisCli -h $RedisHost --raw @Arguments
    }

    if ($LASTEXITCODE -ne 0) {
        throw "redis-cli failed with exit code $LASTEXITCODE (host: $RedisHost, command: $($Arguments -join ' '))."
    }

    # redis-cli 在 --raw 模式下可能多输出一个空行；去掉尾部空元素，
    # 这样 GET 返回字符串，BLPOP 返回 key/value 两项。
    $output = @($output)
    while ($output.Count -gt 1 -and [string]::IsNullOrEmpty([string]$output[-1])) {
        $output = @($output[0..($output.Count - 2)])
    }
    if ($output.Count -eq 1) {
        return $output[0]
    }
    return $output
}

Export-ModuleMember -Function Write-PipelineLog, Send-WechatMessage, Send-PipelineNotification, Invoke-RedisCli
