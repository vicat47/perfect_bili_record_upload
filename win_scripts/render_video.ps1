#Requires -Version 5.1

<#
.SYNOPSIS
    从 Redis 渲染队列取任务，调用 RenderVideo 模块编码。

.DESCRIPTION
    任务格式：{"filename":"2025-08-17_21-35-28.mkv","bvid":"BV..."}
    成功后将 {"filename":"2025-08-17_21-35-28.mp4","bvid":"BV..."} 推入 biliup:upload-list。
    失败时推入 biliup:render-failed，方便后续排查/重试。

    配置文件默认是脚本目录下的 render.config.psd1。
    首次使用请复制 render.config.example.psd1 并填写。

.EXAMPLE
    .\render_video.ps1 -waitForNewTask

.EXAMPLE
    .\render_video.ps1 -ValidateOnly

.EXAMPLE
    .\render_video.ps1 -noUpload -noProgress
#>
[CmdletBinding()]
param(
    [switch]$waitForNewTask,
    [switch]$shutdown,
    [switch]$noUpload,
    [switch]$noProgress,
    [switch]$ValidateOnly,
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'render.config.psd1')
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PerfectBili.Common\PerfectBili.Common.psd1') -Force
Import-Module (Join-Path $PSScriptRoot 'RenderVideo\RenderVideo.psd1') -Force

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found: $ConfigPath. Copy render.config.example.psd1 to render.config.psd1 and edit it."
}

$script:Config = Import-PowerShellDataFile -LiteralPath $ConfigPath

function Assert-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    foreach ($key in @('NotifyUrl', 'WechatTarget', 'RedisHost', 'InputPath', 'OutputPath')) {
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

$script:RenderOptions = @{
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

if ($script:Config.ContainsKey('Render') -and $script:Config.Render) {
    foreach ($key in $script:Config.Render.Keys) {
        $script:RenderOptions[$key] = $script:Config.Render[$key]
    }
}

function Resolve-TaskPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Filename
    )

    if ([IO.Path]::IsPathRooted($Filename)) {
        return $Filename
    }
    return Join-Path $script:Config.InputPath $Filename
}

function Set-RenderState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json
    )

    $null = Invoke-RedisCli -RedisHost $script:Config.RedisHost -Arguments @('SET', 'biliup:processing:rendering') -InputValue $Json
}

function Clear-RenderState {
    [CmdletBinding()]
    param()

    try {
        $null = Invoke-RedisCli -RedisHost $script:Config.RedisHost -Arguments @('DEL', 'biliup:processing:rendering')
    }
    catch {
        Write-PipelineLog -Level WARN -Message "Failed to clear biliup:processing:rendering: $($_.Exception.Message)"
    }
}

function Push-UploadTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json
    )

    $null = Invoke-RedisCli -RedisHost $script:Config.RedisHost -Arguments @('RPUSH', 'biliup:upload-list') -InputValue $Json
}

function Push-RenderFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json
    )

    try {
        $null = Invoke-RedisCli -RedisHost $script:Config.RedisHost -Arguments @('RPUSH', 'biliup:render-failed') -InputValue $Json
    }
    catch {
        Write-PipelineLog -Level WARN -Message "Failed to push biliup:render-failed: $($_.Exception.Message)"
    }
}

function Invoke-RenderTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Task
    )

    $taskJson = ConvertTo-Json -Compress -InputObject $Task
    $stateSet = $false
    $success = $false
    $payloadJson = $null
    $outputName = $null

    try {
        if ([string]::IsNullOrWhiteSpace([string]$Task.filename) -or [string]::IsNullOrWhiteSpace([string]$Task.bvid)) {
            throw "Invalid render task: $taskJson"
        }

        $inputPath = Resolve-TaskPath -Filename $Task.filename
        $inputItem = Get-Item -LiteralPath $inputPath -ErrorAction Stop
        if ($inputItem.PSIsContainer) {
            throw "Input path is a directory: $inputPath"
        }

        $baseName = [IO.Path]::GetFileNameWithoutExtension($inputItem.Name)
        $outputName = "$baseName.mp4"
        $outputPath = Join-Path $script:Config.OutputPath $outputName

        $logPath = $null
        if ($script:Config.ContainsKey('LogDirectory') -and -not [string]::IsNullOrWhiteSpace([string]$script:Config.LogDirectory)) {
            $logPath = Join-Path $script:Config.LogDirectory "$baseName.ffmpeg.log"
        }

        $payload = @{
            filename = $outputName
            bvid     = $Task.bvid
        }
        $payloadJson = ConvertTo-Json -Compress -InputObject $payload

        Set-RenderState -Json $payloadJson
        $stateSet = $true

        Write-PipelineLog "Start rendering: $($Task.filename)"

        $renderArgs = @{
            InputPath  = $inputItem.FullName
            OutputPath = $outputPath
            Overwrite  = $true
        }
        foreach ($key in $script:RenderOptions.Keys) {
            $renderArgs[$key] = $script:RenderOptions[$key]
        }
        if ($logPath) {
            $renderArgs.LogPath = $logPath
        }
        if ($noProgress) {
            $renderArgs.NoProgress = $true
        }

        $result = Invoke-VideoRender @renderArgs
        $success = $true

        Write-PipelineLog "Finished rendering: $outputName ($([math]::Round($result.Elapsed.TotalMinutes, 2)) min, $([math]::Round($result.OutputSizeBytes / 1GB, 2)) GiB)"
        Send-PipelineNotification -Config $script:Config -Content "$($Task.filename) 渲染完毕"
    }
    catch {
        Write-PipelineLog -Level ERROR -Message "Render failed: $($Task.filename): $($_.Exception.Message)"
        Send-PipelineNotification -Config $script:Config -Content "$($Task.filename) 渲染失败: $($_.Exception.Message)"
        Push-RenderFailure -Json $taskJson
    }
    finally {
        if ($stateSet) {
            Clear-RenderState
        }
    }

    if ($success -and -not $noUpload) {
        try {
            Push-UploadTask -Json $payloadJson
            Write-PipelineLog "Queued for upload: $outputName"
        }
        catch {
            Write-PipelineLog -Level ERROR -Message "Failed to queue upload for ${outputName}: $($_.Exception.Message)"
            Push-RenderFailure -Json $taskJson
        }
    }

    return $success
}

function Main {
    while ($true) {
        $timeout = if ($waitForNewTask.IsPresent) { '0' } else { '5' }

        try {
            $result = Invoke-RedisCli -RedisHost $script:Config.RedisHost -Arguments @('BLPOP', 'biliup:render-list', $timeout)
        }
        catch {
            Write-PipelineLog -Level ERROR -Message "Redis BLPOP failed: $($_.Exception.Message)"
            Start-Sleep -Seconds 10
            continue
        }

        if (-not $result -or @($result).Count -lt 2) {
            Write-PipelineLog 'No value found in biliup:render-list.'
            break
        }

        $taskJson = [string]$result[1]
        try {
            $task = ConvertFrom-Json -InputObject $taskJson -ErrorAction Stop
        }
        catch {
            Write-PipelineLog -Level ERROR -Message "Invalid task JSON: $taskJson"
            Push-RenderFailure -Json $taskJson
            continue
        }

        try {
            $null = Invoke-RenderTask -Task $task
        }
        catch {
            Write-PipelineLog -Level ERROR -Message "Unexpected render error: $($_.Exception.Message)"
            Push-RenderFailure -Json $taskJson
        }
    }

    if ($shutdown.IsPresent) {
        shutdown.exe -f -s -t 60
    }
}

if ($ValidateOnly.IsPresent) {
    Write-PipelineLog "Config: $ConfigPath"
    Write-PipelineLog "Redis: $($script:Config.RedisHost)"
    Write-PipelineLog "Input: $($script:Config.InputPath)"
    Write-PipelineLog "Output: $($script:Config.OutputPath)"

    if (-not (Get-Command -Name 'redis-cli' -ErrorAction SilentlyContinue)) {
        throw 'redis-cli not found in PATH.'
    }
    if (-not (Test-Path -LiteralPath $script:Config.InputPath -PathType Container)) {
        throw "InputPath does not exist: $($script:Config.InputPath)"
    }
    if (Test-Path -LiteralPath $script:Config.OutputPath -PathType Leaf) {
        throw "OutputPath is a file, not a directory: $($script:Config.OutputPath)"
    }
    if (-not (Test-Path -LiteralPath $script:Config.OutputPath -PathType Container)) {
        Write-PipelineLog -Level WARN -Message "OutputPath does not exist yet; it will be created on first render."
    }
    if ($script:Config.ContainsKey('LogDirectory') -and -not [string]::IsNullOrWhiteSpace([string]$script:Config.LogDirectory)) {
        if (-not (Test-Path -LiteralPath $script:Config.LogDirectory -PathType Container)) {
            Write-PipelineLog -Level WARN -Message 'LogDirectory does not exist yet; it will be created on first render.'
        }
    }

    $validParameters = (Get-Command -Name 'Invoke-VideoRender').Parameters.Keys
    foreach ($key in $script:RenderOptions.Keys) {
        if ($key -notin $validParameters) {
            throw "Unknown Render option '$key' in $ConfigPath."
        }
    }

    Test-RenderEnvironment
    Write-PipelineLog 'Validation OK.'
    return
}

Main
