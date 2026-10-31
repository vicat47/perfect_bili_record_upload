#Requires -Version 5.1

<#
.SYNOPSIS
    从 Redis 上传队列取任务，调用 biliup 上传到 Bilibili。

.DESCRIPTION
    任务格式：{"filename":"2025-08-17_21-35-28.mp4","bvid":"BV..."}
    成功/失败都会清理 biliup:processing:uploading；失败任务会进入 biliup:upload-failed。

    配置文件默认是脚本目录下的 upload.config.psd1。
    首次使用请复制 upload.config.example.psd1 并填写。

.EXAMPLE
    .\upload_video.ps1

.EXAMPLE
    .\upload_video.ps1 -ValidateOnly
#>
[CmdletBinding()]
param(
    [switch]$ValidateOnly,
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'upload.config.psd1')
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PerfectBili.Common\PerfectBili.Common.psd1') -Force

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found: $ConfigPath. Copy upload.config.example.psd1 to upload.config.psd1 and edit it."
}

$script:Config = Import-PowerShellDataFile -LiteralPath $ConfigPath

function Assert-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    foreach ($key in @('NotifyUrl', 'WechatTarget', 'RedisHost', 'OutputPath')) {
        if (-not $Config.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$Config[$key])) {
            throw "Config key '$key' is missing or empty."
        }
    }

    if ($Config.RedisHost -match '^your[\.-]' -or
        $Config.NotifyUrl -match 'your-nodered-domain' -or
        $Config.WechatTarget -match '^your_') {
        throw "Config still contains example values. Edit $ConfigPath."
    }

    if ($Config.ContainsKey('Auth') -and $Config.Auth) {
        $authType = [string]$Config.Auth.Type
        if ($authType -notin @('', 'none', 'basic', 'bearer')) {
            throw "Unsupported Auth.Type '$authType'. Use basic, bearer or none."
        }
        if ($authType -in @('basic', 'bearer') -and [string]::IsNullOrWhiteSpace([string]$Config.Auth.Password)) {
            throw "Config Auth.Password is required for Auth.Type '$authType'."
        }
        if ($authType -in @('basic', 'bearer') -and $Config.Auth.Password -match '^your_.*(placeholder|token)') {
            throw "Config still contains example Auth.Password. Edit $ConfigPath."
        }
    }
}

Assert-Config -Config $script:Config

$script:BiliupPath = if ($script:Config.ContainsKey('BiliupPath') -and -not [string]::IsNullOrWhiteSpace([string]$script:Config.BiliupPath)) {
    [string]$script:Config.BiliupPath
}
else {
    'biliup'
}

$script:BiliupArgs = @('-l', 'qn', '--limit', '6')
if ($script:Config.ContainsKey('BiliupArgs') -and $script:Config.BiliupArgs) {
    $script:BiliupArgs = @($script:Config.BiliupArgs)
}

function Resolve-UploadPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Filename
    )

    if ([IO.Path]::IsPathRooted($Filename)) {
        return $Filename
    }
    return Join-Path $script:Config.OutputPath $Filename
}

function Set-UploadState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json
    )

    $null = Invoke-RedisCli -RedisHost $script:Config.RedisHost -Arguments @('SET', 'biliup:processing:uploading') -InputValue $Json
}

function Clear-UploadState {
    [CmdletBinding()]
    param()

    try {
        $null = Invoke-RedisCli -RedisHost $script:Config.RedisHost -Arguments @('DEL', 'biliup:processing:uploading')
    }
    catch {
        Write-PipelineLog -Level WARN -Message "Failed to clear biliup:processing:uploading: $($_.Exception.Message)"
    }
}

function Push-UploadFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json
    )

    try {
        $null = Invoke-RedisCli -RedisHost $script:Config.RedisHost -Arguments @('RPUSH', 'biliup:upload-failed') -InputValue $Json
    }
    catch {
        Write-PipelineLog -Level WARN -Message "Failed to push biliup:upload-failed: $($_.Exception.Message)"
    }
}

function Invoke-UploadTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Task
    )

    $taskJson = ConvertTo-Json -Compress -InputObject $Task
    $stateSet = $false

    try {
        if ([string]::IsNullOrWhiteSpace([string]$Task.filename) -or [string]::IsNullOrWhiteSpace([string]$Task.bvid)) {
            throw "Invalid upload task: $taskJson"
        }

        $filePath = Resolve-UploadPath -Filename $Task.filename
        $fileItem = Get-Item -LiteralPath $filePath -ErrorAction Stop
        if ($fileItem.PSIsContainer) {
            throw "Upload path is a directory: $filePath"
        }

        $payload = @{
            filename = $Task.filename
            bvid     = $Task.bvid
        }
        $payloadJson = ConvertTo-Json -Compress -InputObject $payload

        Set-UploadState -Json $payloadJson
        $stateSet = $true

        Write-PipelineLog "Start uploading: $($Task.filename)"

        $biliupArgs = @('append') + $script:BiliupArgs + @('--vid', $Task.bvid, $fileItem.FullName)
        & $script:BiliupPath @biliupArgs
        if ($LASTEXITCODE -ne 0) {
            throw "biliup failed with exit code $LASTEXITCODE"
        }

        Write-PipelineLog "Upload finished: $($Task.filename)"
        Send-PipelineNotification -Config $script:Config -Content "$($Task.filename) 上传完毕"
    }
    catch {
        Write-PipelineLog -Level ERROR -Message "Upload failed: $($Task.filename): $($_.Exception.Message)"
        Send-PipelineNotification -Config $script:Config -Content "$($Task.filename) 上传失败: $($_.Exception.Message)"
        Push-UploadFailure -Json $taskJson
    }
    finally {
        if ($stateSet) {
            Clear-UploadState
        }
    }
}

if ($ValidateOnly.IsPresent) {
    Write-PipelineLog "Config: $ConfigPath"
    Write-PipelineLog "Redis: $($script:Config.RedisHost)"
    Write-PipelineLog "Output: $($script:Config.OutputPath)"
    Write-PipelineLog "Biliup: $script:BiliupPath"

    if (-not (Get-Command -Name 'redis-cli' -ErrorAction SilentlyContinue)) {
        throw 'redis-cli not found in PATH.'
    }
    if (-not (Get-Command -Name $script:BiliupPath -ErrorAction SilentlyContinue)) {
        throw "biliup not found: $script:BiliupPath"
    }
    if (-not (Test-Path -LiteralPath $script:Config.OutputPath -PathType Container)) {
        throw "OutputPath does not exist or is not a directory: $($script:Config.OutputPath)"
    }

    Write-PipelineLog 'Validation OK.'
    return
}

while ($true) {
    try {
        $result = Invoke-RedisCli -RedisHost $script:Config.RedisHost -Arguments @('BLPOP', 'biliup:upload-list', '0')
    }
    catch {
        Write-PipelineLog -Level ERROR -Message "Redis BLPOP failed: $($_.Exception.Message)"
        Start-Sleep -Seconds 10
        continue
    }

    if (-not $result -or @($result).Count -lt 2) {
        Start-Sleep -Seconds 1
        continue
    }

    $taskJson = [string]$result[1]
    try {
        $task = ConvertFrom-Json -InputObject $taskJson -ErrorAction Stop
    }
    catch {
        Write-PipelineLog -Level ERROR -Message "Invalid task JSON: $taskJson"
        Push-UploadFailure -Json $taskJson
        continue
    }

    try {
        $null = Invoke-UploadTask -Task $task
    }
    catch {
        Write-PipelineLog -Level ERROR -Message "Unexpected upload error: $($_.Exception.Message)"
        Push-UploadFailure -Json $taskJson
    }
}
