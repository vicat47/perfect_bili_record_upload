#Requires -Version 5.1

<#
.SYNOPSIS
    将视频文件加入 biliup:render-list。

.DESCRIPTION
    读取脚本目录下的 bvid.txt 作为目标 BVID，然后把拖入/传入的文件推入 Redis 渲染队列。
    队列里的 filename 使用文件的完整路径，render_video.ps1 可以直接处理。

.EXAMPLE
    .\enqueue_render.ps1 'D:\record\2025-08-17_21-35-28.mkv'

.EXAMPLE
    .\enqueue_render.ps1 'D:\record\a.mkv','D:\record\b.mkv' -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]]$Files,

    [string]$ConfigPath = (Join-Path $PSScriptRoot 'render.config.psd1'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PerfectBili.Common\PerfectBili.Common.psd1') -Force

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found: $ConfigPath. Copy render.config.example.psd1 to render.config.psd1 and edit it."
}

$script:Config = Import-PowerShellDataFile -LiteralPath $ConfigPath

if (-not $script:Config.ContainsKey('RedisHost') -or [string]::IsNullOrWhiteSpace([string]$script:Config.RedisHost)) {
    throw "Config key 'RedisHost' is missing or empty."
}
if ($script:Config.RedisHost -match '^your[\.-]') {
    throw "Config still contains example values. Edit $ConfigPath."
}

$bvidPath = Join-Path $PSScriptRoot 'bvid.txt'
if (-not (Test-Path -LiteralPath $bvidPath -PathType Leaf)) {
    throw "bvid.txt not found: $bvidPath"
}

$bvid = (Get-Content -LiteralPath $bvidPath -Raw).Trim()
if ($bvid -notmatch '^BV[0-9A-Za-z]+$') {
    throw "Invalid BVID in bvid.txt: $bvid"
}

foreach ($file in $Files) {
    $item = Get-Item -LiteralPath $file -ErrorAction Stop
    if ($item.PSIsContainer) {
        throw "Path is a directory: $file"
    }

    $payload = @{
        filename = $item.FullName
        bvid     = $bvid
    }
    $json = ConvertTo-Json -Compress -InputObject $payload

    if ($DryRun.IsPresent) {
        Write-PipelineLog "DRY-RUN: $json"
        continue
    }

    $null = Invoke-RedisCli -RedisHost $script:Config.RedisHost -Arguments @('RPUSH', 'biliup:render-list') -InputValue $json
    Write-PipelineLog "Queued: $($item.FullName)"
}
