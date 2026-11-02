#Requires -Version 5.1

function Resolve-Executable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NameOrPath,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    $command = Get-Command -Name $NameOrPath -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "$DisplayName not found: '$NameOrPath'. Install it or pass an explicit path."
    }

    if (-not [string]::IsNullOrWhiteSpace($command.Source)) {
        return $command.Source
    }
    if (-not [string]::IsNullOrWhiteSpace($command.Path)) {
        return $command.Path
    }
    return $command.Name
}

function Format-ProcessArgument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Argument
    )

    if ($Argument -match '[\s"]') {
        return '"' + ($Argument -replace '"', '\"') + '"'
    }
    return $Argument
}

function Format-FfmpegProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    function Get-Value {
        param(
            [string]$Key,
            [string]$Default
        )
        if ($State.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace($State[$Key])) {
            return $State[$Key]
        }
        return $Default
    }

    $frame = Get-Value -Key 'frame' -Default '0'
    $fps = Get-Value -Key 'computed_fps' -Default (Get-Value -Key 'fps' -Default '0.00')
    $q = Get-Value -Key 'stream_0_0_q' -Default (Get-Value -Key 'q' -Default '0.0')
    $time = Get-Value -Key 'out_time' -Default '00:00:00.00'
    $speed = Get-Value -Key 'speed' -Default 'N/A'

    $sizeBytes = 0L
    if ($State.ContainsKey('total_size')) {
        [void][long]::TryParse($State['total_size'], [ref]$sizeBytes)
    }
    if ($sizeBytes -ge 1GB) {
        $sizeText = '{0,8:F2}GiB' -f ($sizeBytes / 1GB)
    }
    elseif ($sizeBytes -ge 1MB) {
        $sizeText = '{0,8:F2}MiB' -f ($sizeBytes / 1MB)
    }
    else {
        $sizeText = '{0,8:F0}kB' -f ($sizeBytes / 1KB)
    }

    $bitrateValue = 0.0
    $bitrateText = '       N/A'
    if ($State.ContainsKey('bitrate')) {
        $bitrateRaw = $State['bitrate'].Trim() -replace ',', ''
        if ($bitrateRaw -match '^([0-9]+(?:\.[0-9]+)?)') {
            $bitrateValue = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
            $bitrateText = '{0,10:F1}kbits/s' -f $bitrateValue
        }
    }

    if ($time -match '^(-?)(\d{2}:\d{2}:\d{2})\.(\d{2})') {
        $time = "$($Matches[1])$($Matches[2]).$($Matches[3])"
    }

    'frame={0,7} fps={1,6} q={2,5} size={3} time={4} bitrate={5} speed={6}' -f $frame, $fps, $q, $sizeText, $time, $bitrateText, $speed
}

function Invoke-FFmpegProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFmpegPath,

        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,

        [bool]$ShowProgress = $true,
        [bool]$VerboseOutput = $false
    )

    $logLines = [System.Collections.Generic.List[string]]::new()
    $state = @{}
    $lastProgressLength = 0
    $progressSeen = $false

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $FFmpegPath @ArgumentList 2>&1 | ForEach-Object {
            $line = $_.ToString()
            if ($line -match '^([A-Za-z0-9_]+)=(.*)$' -and $Matches[1] -in @(
                    'frame', 'fps', 'stream_0_0_q', 'q', 'total_size',
                    'out_time_us', 'out_time_ms', 'out_time', 'dup_frames',
                    'drop_frames', 'speed', 'bitrate', 'progress'
                )) {
                $key = $Matches[1]
                $value = $Matches[2]
                $state[$key] = $value

                if ($key -eq 'progress') {
                    $progressSeen = $true
                    $frameValue = 0L
                    if ($state.ContainsKey('frame')) {
                        [void][long]::TryParse($state['frame'], [ref]$frameValue)
                    }

                    $outSeconds = 0.0
                    if ($state.ContainsKey('out_time') -and $state['out_time'].Trim() -match '^(-?)(\d{2}):(\d{2}):(\d{2})\.(\d+)') {
                        $sign = if ($Matches[1] -eq '-') { -1 } else { 1 }
                        $outSeconds = $sign * (
                            ([double]$Matches[2] * 3600) +
                            ([double]$Matches[3] * 60) +
                            [double]$Matches[4]
                        )
                    }

                    if ($frameValue -gt 0 -and $outSeconds -gt 0 -and
                        $state.ContainsKey('speed') -and
                        $state['speed'].Trim() -match '^([0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)x') {
                        $speedValue = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
                        $sourceFps = $frameValue / $outSeconds
                        $state['computed_fps'] = ($sourceFps * $speedValue).ToString('F2', [Globalization.CultureInfo]::InvariantCulture)
                    }

                    if ($ShowProgress) {
                        $text = Format-FfmpegProgress -State $state
                        if ($text.Length -lt $lastProgressLength) {
                            $text += ' ' * ($lastProgressLength - $text.Length)
                        }
                        $lastProgressLength = $text.Length
                        Write-Host "`r$text" -NoNewline
                    }
                    if ($value -eq 'end' -and $ShowProgress) {
                        Write-Host ''
                    }
                }
            }
            else {
                $logLines.Add($line)
                if ($VerboseOutput) {
                    Write-Verbose $line
                }
            }
        }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    if ($ShowProgress -and $progressSeen -and $state['progress'] -ne 'end') {
        Write-Host ''
    }

    [pscustomobject]@{
        ExitCode     = $exitCode
        LogLines     = @($logLines)
        ProgressSeen = $progressSeen
    }
}

function Test-RenderEnvironment {
    <#
    .SYNOPSIS
        检查 ffmpeg / ffprobe 是否可用，以及当前 ffmpeg 是否带 NVENC 编码器。
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$FFmpegPath = 'ffmpeg',
        [string]$FFprobePath = 'ffprobe'
    )

    $ffmpeg = Resolve-Executable -NameOrPath $FFmpegPath -DisplayName 'ffmpeg'
    $ffprobeCommand = Get-Command -Name $FFprobePath -ErrorAction SilentlyContinue

    $versionLine = (& $ffmpeg -version 2>&1 | Select-Object -First 1)
    $encoderText = (& $ffmpeg -hide_banner -encoders 2>&1 | Out-String)

    [pscustomobject]@{
        FFmpegPath    = $ffmpeg
        FFmpegVersion = [string]$versionLine
        FFprobePath   = if ($ffprobeCommand) { $ffprobeCommand.Source } else { $null }
        HasH264Nvenc  = [bool]($encoderText -match '(?m)^\s*V[\.\w]*\s+h264_nvenc\s')
        HasHevcNvenc  = [bool]($encoderText -match '(?m)^\s*V[\.\w]*\s+hevc_nvenc\s')
        HasLibX264    = [bool]($encoderText -match '(?m)^\s*V[\.\w]*\s+libx264\s')
    }
}

function Get-VideoInfo {
    <#
    .SYNOPSIS
        用 ffprobe 读取媒体文件的基本信息。
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName', 'Path')]
        [string]$InputPath,

        [string]$FFprobePath = 'ffprobe'
    )

    begin {
        $ffprobe = Resolve-Executable -NameOrPath $FFprobePath -DisplayName 'ffprobe'
    }

    process {
        $inputItem = Get-Item -LiteralPath $InputPath -ErrorAction Stop
        if ($inputItem.PSIsContainer) {
            throw "InputPath is a directory: $($inputItem.FullName)"
        }

        $oldErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $jsonText = (& $ffprobe -v error -print_format json -show_format -show_streams $inputItem.FullName 2>&1 | Out-String)
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $oldErrorActionPreference
        }

        if ($exitCode -ne 0) {
            throw "ffprobe failed with exit code $exitCode.`n$($jsonText.Trim())"
        }

        $info = $jsonText | ConvertFrom-Json

        [pscustomobject]@{
            InputPath       = $inputItem.FullName
            DurationSeconds = [double]$info.format.duration
            SizeBytes       = [long]$info.format.size
            FormatName      = [string]$info.format.format_name
            VideoStreams    = @($info.streams | Where-Object { $_.codec_type -eq 'video' })
            AudioStreams    = @($info.streams | Where-Object { $_.codec_type -eq 'audio' })
            Raw             = $info
        }
    }
}

function Invoke-VideoRender {
    <#
    .SYNOPSIS
        使用 ffmpeg 编码一个视频文件。只负责编码，不涉及 Redis / 微信 / 上传。

    .DESCRIPTION
        默认使用 h264_nvenc，也可以在 -VideoCodec 中指定 hevc_nvenc、libx264 或 copy。
        输出先写入同目录的 .part 文件，成功后再替换目标文件；失败会删除 .part。
        默认显示 ffmpeg 风格进度；加 -NoProgress 可关闭。

    .EXAMPLE
        Invoke-VideoRender -InputPath .\a.mkv -OutputPath .\out\a.mp4

    .EXAMPLE
        Invoke-VideoRender -InputPath .\a.mkv -OutputPath .\out\a.mp4 `
            -VideoCodec h264_nvenc -Preset p5 -Cq 19 `
            -VideoBitrate 20000k -MaxBitrate 30000k -BufferSize 30000k `
            -Width 2844 -Height 1600 -FastStart
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('FullName', 'Path')]
        [string]$InputPath,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$OutputPath,

        [ValidateSet('h264_nvenc', 'hevc_nvenc', 'libx264', 'copy')]
        [string]$VideoCodec = 'h264_nvenc',

        [ValidateSet('aac', 'libopus', 'copy', 'none')]
        [string]$AudioCodec = 'aac',

        [string]$VideoBitrate = '20000k',
        [string]$MaxBitrate = '30000k',
        [string]$BufferSize = '30000k',

        # NVENC 对应 -cq，libx264 对应 -crf。设为 -1 表示不用质量模式，改用 VideoBitrate。
        [ValidateRange(-1, 51)]
        [int]$Cq = 19,

        [string]$Preset,
        [string]$VideoProfile = 'main',
        [string]$PixelFormat = 'yuv420p',

        [ValidateRange(0, 16384)]
        [int]$Width = 0,

        [ValidateRange(0, 16384)]
        [int]$Height = 0,

        [ValidateRange(0, 32)]
        [int]$AudioTrack = 0,

        [switch]$AllAudio,
        [switch]$NoAudio,
        [string]$AudioBitrate = '320k',

        [switch]$FastStart,
        [switch]$Overwrite,

        [ValidateSet('quiet', 'panic', 'fatal', 'error', 'warning', 'info', 'verbose', 'debug')]
        [string]$LogLevel = 'warning',

        [string]$LogPath,
        [string]$FFmpegPath = 'ffmpeg',
        [string[]]$ExtraFFmpegArgs = @(),
        [switch]$NoProgress,
        [switch]$DryRun
    )

    $inputItem = Get-Item -LiteralPath $InputPath -ErrorAction Stop
    if ($inputItem.PSIsContainer) {
        throw "InputPath is a directory: $($inputItem.FullName)"
    }
    $inputFull = $inputItem.FullName

    $outputFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    $outputExtension = [IO.Path]::GetExtension($outputFull)
    if ([string]::IsNullOrWhiteSpace($outputExtension)) {
        throw "OutputPath must include a file extension: $OutputPath"
    }
    if ($inputFull -eq $outputFull) {
        throw 'OutputPath must be different from InputPath.'
    }
    if ((Test-Path -LiteralPath $outputFull) -and -not $Overwrite) {
        throw "Output file already exists: $outputFull. Use -Overwrite to replace it."
    }
    if ($VideoCodec -eq 'copy' -and ($Width -gt 0 -or $Height -gt 0)) {
        throw 'Width/Height cannot be used with -VideoCodec copy.'
    }

    $ffmpeg = Resolve-Executable -NameOrPath $FFmpegPath -DisplayName 'ffmpeg'
    $argumentList = [System.Collections.Generic.List[string]]::new()

    function Add-Argument {
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$Value
        )
        [void]$argumentList.Add($Value)
    }

    Add-Argument '-hide_banner'
    Add-Argument '-nostdin'
    Add-Argument '-loglevel'
    Add-Argument $LogLevel
    Add-Argument '-nostats'
    Add-Argument '-progress'
    Add-Argument 'pipe:1'
    if ($Overwrite) {
        Add-Argument '-y'
    }
    else {
        Add-Argument '-n'
    }
    Add-Argument '-i'
    Add-Argument $inputFull
    Add-Argument '-map'
    Add-Argument '0:v:0'

    $includeAudio = (-not $NoAudio) -and ($AudioCodec -ne 'none')
    if ($includeAudio) {
        if ($AllAudio) {
            Add-Argument '-map'
            Add-Argument '0:a?'
        }
        else {
            Add-Argument '-map'
            Add-Argument "0:a:${AudioTrack}?"
        }
    }

    if ($VideoCodec -eq 'copy') {
        Add-Argument '-c:v'
        Add-Argument 'copy'
    }
    else {
        Add-Argument '-c:v'
        Add-Argument $VideoCodec

        if ($VideoCodec -like '*_nvenc') {
            $presetToUse = if ([string]::IsNullOrWhiteSpace($Preset)) { 'p5' } else { $Preset }
            Add-Argument '-preset'
            Add-Argument $presetToUse
            Add-Argument '-rc:v'
            Add-Argument 'vbr'
            if ($Cq -ge 0) {
                Add-Argument '-cq:v'
                Add-Argument ([string]$Cq)
            }
            if (-not [string]::IsNullOrWhiteSpace($VideoBitrate)) {
                Add-Argument '-b:v'
                Add-Argument $VideoBitrate
            }
        }
        else {
            $presetToUse = if ([string]::IsNullOrWhiteSpace($Preset)) { 'medium' } else { $Preset }
            Add-Argument '-preset'
            Add-Argument $presetToUse
            if ($Cq -ge 0) {
                Add-Argument '-crf'
                Add-Argument ([string]$Cq)
            }
            elseif (-not [string]::IsNullOrWhiteSpace($VideoBitrate)) {
                Add-Argument '-b:v'
                Add-Argument $VideoBitrate
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($MaxBitrate)) {
            Add-Argument '-maxrate:v'
            Add-Argument $MaxBitrate
        }
        if (-not [string]::IsNullOrWhiteSpace($BufferSize)) {
            Add-Argument '-bufsize:v'
            Add-Argument $BufferSize
        }
        if (-not [string]::IsNullOrWhiteSpace($VideoProfile)) {
            Add-Argument '-profile:v'
            Add-Argument $VideoProfile
        }
        if (-not [string]::IsNullOrWhiteSpace($PixelFormat)) {
            Add-Argument '-pix_fmt'
            Add-Argument $PixelFormat
        }

        if ($Width -gt 0 -and $Height -gt 0) {
            Add-Argument '-vf'
            Add-Argument "scale=$Width`:$Height"
        }
        elseif ($Width -gt 0) {
            Add-Argument '-vf'
            Add-Argument "scale=$Width`:-2"
        }
        elseif ($Height -gt 0) {
            Add-Argument '-vf'
            Add-Argument "scale=-2`:$Height"
        }
    }

    if (-not $includeAudio) {
        Add-Argument '-an'
    }
    elseif ($AudioCodec -eq 'copy') {
        Add-Argument '-c:a'
        Add-Argument 'copy'
    }
    else {
        Add-Argument '-c:a'
        Add-Argument $AudioCodec
        if (-not [string]::IsNullOrWhiteSpace($AudioBitrate)) {
            Add-Argument '-b:a'
            Add-Argument $AudioBitrate
        }
    }

    if ($FastStart -and $outputExtension -in @('.mp4', '.m4v', '.mov')) {
        Add-Argument '-movflags'
        Add-Argument '+faststart'
    }

    if ($ExtraFFmpegArgs -and $ExtraFFmpegArgs.Count -gt 0) {
        foreach ($extraArg in $ExtraFFmpegArgs) {
            Add-Argument $extraArg
        }
    }

    $logFull = $null
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $logFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)
    }

    $tempOutput = "$outputFull.part$outputExtension"
    if ($logFull) {
        if ($logFull -eq $inputFull -or $logFull -eq $outputFull -or $logFull -eq $tempOutput) {
            throw 'LogPath must be different from InputPath, OutputPath, and the temporary output path.'
        }
        if (Test-Path -LiteralPath $logFull -PathType Container) {
            throw "LogPath is a directory: $logFull"
        }
    }
    Add-Argument $tempOutput

    $ffmpegArgArray = $argumentList.ToArray()
    $displayCommand = "$ffmpeg " + (($ffmpegArgArray | ForEach-Object { Format-ProcessArgument -Argument $_ }) -join ' ')

    $resultBase = [ordered]@{
        InputPath   = $inputFull
        OutputPath  = $outputFull
        CommandLine = $displayCommand
    }

    if ($DryRun) {
        $resultBase.Success = $true
        $resultBase.DryRun = $true
        $resultBase.ExitCode = $null
        return [pscustomobject]$resultBase
    }

    if (-not $PSCmdlet.ShouldProcess($outputFull, 'Render video')) {
        $resultBase.Success = $true
        $resultBase.Skipped = $true
        $resultBase.ExitCode = $null
        return [pscustomobject]$resultBase
    }

    $outputDirectory = [IO.Path]::GetDirectoryName($outputFull)
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    if ($logFull) {
        $logDirectory = [IO.Path]::GetDirectoryName($logFull)
        if ($logDirectory -and -not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        }
    }

    if (Test-Path -LiteralPath $tempOutput) {
        Remove-Item -LiteralPath $tempOutput -Force
    }

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $processResult = Invoke-FFmpegProcess `
            -FFmpegPath $ffmpeg `
            -ArgumentList $ffmpegArgArray `
            -ShowProgress (-not $NoProgress.IsPresent) `
            -VerboseOutput ($VerbosePreference -ne 'SilentlyContinue')
        $ffmpegOutput = $processResult.LogLines
        $exitCode = $processResult.ExitCode
    }
    finally {
        $stopwatch.Stop()
    }

    $logText = ($ffmpegOutput -join [Environment]::NewLine).TrimEnd()
    if ($logFull) {
        [IO.File]::WriteAllText($logFull, $logText, [Text.UTF8Encoding]::new($false))
    }

    if ($exitCode -ne 0) {
        if (Test-Path -LiteralPath $tempOutput) {
            Remove-Item -LiteralPath $tempOutput -Force
        }
        $tail = ($ffmpegOutput | Select-Object -Last 30) -join [Environment]::NewLine
        throw "ffmpeg failed with exit code $exitCode.`n$tail"
    }

    if (-not (Test-Path -LiteralPath $tempOutput -PathType Leaf)) {
        throw "ffmpeg returned exit code 0 but the output file was not created: $tempOutput"
    }

    try {
        Move-Item -LiteralPath $tempOutput -Destination $outputFull -Force
    }
    catch {
        throw "Failed to move the rendered file to '$outputFull'. The temporary file was kept at '$tempOutput'. $($_.Exception.Message)"
    }

    $outputItem = Get-Item -LiteralPath $outputFull

    [pscustomobject]@{
        InputPath       = $inputFull
        OutputPath      = $outputFull
        Success         = $true
        ExitCode        = 0
        Elapsed         = $stopwatch.Elapsed
        OutputSizeBytes = $outputItem.Length
        CommandLine     = $displayCommand
        LogPath         = $logFull
    }
}

function ConvertTo-SecondValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $trimmed = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'Time point cannot be empty.'
    }

    $invariant = [Globalization.CultureInfo]::InvariantCulture
    try {
        if ($trimmed -match '^\d+(\.\d+)?$') {
            return [double]::Parse($trimmed, $invariant)
        }

        $parts = $trimmed.Split(':')
        if ($parts.Count -eq 2) {
            $minutes = [double]::Parse($parts[0], $invariant)
            $seconds = [double]::Parse($parts[1], $invariant)
            return ($minutes * 60) + $seconds
        }
        if ($parts.Count -eq 3) {
            $hours = [double]::Parse($parts[0], $invariant)
            $minutes = [double]::Parse($parts[1], $invariant)
            $seconds = [double]::Parse($parts[2], $invariant)
            return ($hours * 3600) + ($minutes * 60) + $seconds
        }
    }
    catch {
        throw "Invalid time point '$Value'. Use seconds, mm:ss, or hh:mm:ss."
    }

    throw "Invalid time point '$Value'. Use seconds, mm:ss, or hh:mm:ss."
}

function Split-Video {
    <#
    .SYNOPSIS
        用 ffmpeg -c copy 按多个时间点快速拆分视频。

    .DESCRIPTION
        输入若干内部时间点，输出：
            0 -> t1, t1 -> t2, ..., 最后一个时间点 -> end
        默认输出到当前目录，文件名为 <输入文件名>_split_<n><扩展名>。
        因为使用 -c copy，不会重新编码，切点会受关键帧限制，实际位置可能略有偏差。
        默认显示 ffmpeg 风格进度；加 -NoProgress 可关闭。

        加 -OnlyInner（别名 -ExcludeEnds）时只输出内部区间：
            t1 -> t2, t2 -> t3, ..., 不输出 0 -> t1 和最后一个时间点 -> end。
        例如 -TimePoint 5,10 -OnlyInner 只输出 5 秒到 10 秒之间的内容。

        时间点支持：
            600          （秒）
            10:00        （分:秒）
            00:10:00     （时:分:秒）
            00:10:00.500 （带毫秒）

        0 和 end 不需要传；第一段总是从 0 开始，最后一段自动到结尾。

    .EXAMPLE
        Split-Video -InputPath .\a.mkv -TimePoint 00:10:00,00:20:00

    .EXAMPLE
        Split-Video .\a.mkv 10:00 20:00

    .EXAMPLE
        Split-Video -InputPath .\a.mkv -TimePoint 600,1200 -OutputDirectory .\out -OutputExtension .mp4

    .EXAMPLE
        Split-Video .\a.mkv 5 10 -OnlyInner
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('FullName', 'Path')]
        [string]$InputPath,

        [Parameter(Mandatory = $true, Position = 1, ValueFromRemainingArguments = $true)]
        [string[]]$TimePoint,

        [string]$OutputDirectory = (Get-Location).Path,
        [string]$OutputName,
        [string]$OutputExtension,

        [ValidateRange(0, 9999)]
        [int]$StartNumber = 1,

        [Alias('ExcludeEnds')]
        [switch]$OnlyInner,

        [switch]$Overwrite,

        [ValidateSet('quiet', 'panic', 'fatal', 'error', 'warning', 'info', 'verbose', 'debug')]
        [string]$LogLevel = 'warning',

        [string]$LogPath,
        [string]$FFmpegPath = 'ffmpeg',
        [string]$FFprobePath = 'ffprobe',
        [string[]]$ExtraFFmpegArgs = @(),
        [switch]$NoProgress,
        [switch]$DryRun
    )

    $inputItem = Get-Item -LiteralPath $InputPath -ErrorAction Stop
    if ($inputItem.PSIsContainer) {
        throw "InputPath is a directory: $($inputItem.FullName)"
    }
    $inputFull = $inputItem.FullName

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = (Get-Location).Path
    }
    $outputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)

    $baseName = if (-not [string]::IsNullOrWhiteSpace($OutputName)) {
        [IO.Path]::GetFileNameWithoutExtension($OutputName)
    }
    else {
        [IO.Path]::GetFileNameWithoutExtension($inputFull)
    }
    if ([string]::IsNullOrWhiteSpace($baseName)) {
        throw 'OutputName is empty.'
    }
    if ($baseName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw "OutputName contains invalid filename characters: $baseName"
    }

    $extension = if (-not [string]::IsNullOrWhiteSpace($OutputExtension)) {
        if (-not $OutputExtension.StartsWith('.')) {
            ".$OutputExtension"
        }
        else {
            $OutputExtension
        }
    }
    else {
        [IO.Path]::GetExtension($inputFull)
    }
    if ([string]::IsNullOrWhiteSpace($extension)) {
        throw 'InputPath has no extension. Specify -OutputExtension.'
    }
    if ($extension -notmatch '^\.[A-Za-z0-9]+$') {
        throw "Invalid output extension: $extension"
    }

    $rawSeconds = @()
    foreach ($timePointValue in $TimePoint) {
        foreach ($timePointPart in $timePointValue.Split(',')) {
            if ([string]::IsNullOrWhiteSpace($timePointPart)) {
                continue
            }
            $rawSeconds += ConvertTo-SecondValue -Value $timePointPart.Trim()
        }
    }

    $negativeTimes = @($rawSeconds | Where-Object { $_ -lt 0 })
    if ($negativeTimes.Count -gt 0) {
        throw "Split time cannot be negative: $($negativeTimes -join ', ')"
    }

    $zeroTimes = @($rawSeconds | Where-Object { $_ -eq 0 })
    if ($zeroTimes.Count -gt 0) {
        Write-Warning 'Ignoring split time 0; the first segment always starts at 0.'
    }

    $positiveTimes = @($rawSeconds | Where-Object { $_ -gt 0 })
    $sortedTimes = @($positiveTimes | Sort-Object -Unique)
    if ($sortedTimes.Count -lt $positiveTimes.Count) {
        Write-Warning 'Duplicate split times were removed.'
    }
    if ($sortedTimes.Count -eq 0) {
        throw 'At least one split time greater than 0 is required.'
    }

    $info = Get-VideoInfo -InputPath $inputFull -FFprobePath $FFprobePath
    if ($info.VideoStreams.Count -eq 0) {
        throw "No video stream found in: $inputFull"
    }
    $duration = [double]$info.DurationSeconds

    $validTimes = @()
    foreach ($splitTime in $sortedTimes) {
        if ($duration -gt 0) {
            if ($splitTime -gt ($duration + 1)) {
                throw "Split time $splitTime exceeds the video duration ($duration seconds)."
            }
            if ($splitTime -ge $duration) {
                Write-Warning "Ignoring split time $splitTime because it is at or after the end of the video ($duration seconds)."
                continue
            }
        }
        $validTimes += $splitTime
    }
    if ($validTimes.Count -eq 0) {
        throw 'No valid internal split points remain.'
    }
    $sortedTimes = @($validTimes)

    $onlyInner = $OnlyInner.IsPresent
    if ($onlyInner -and $sortedTimes.Count -lt 2) {
        throw '-OnlyInner requires at least two time points (for example 5,10).'
    }

    $safeOutputDir = $outputDir -replace '%', '%%'
    $safeBaseName = $baseName -replace '%', '%%'

    $finalFiles = @()
    if ($onlyInner) {
        for ($segmentIndex = 0; $segmentIndex -lt ($sortedTimes.Count - 1); $segmentIndex++) {
            $finalFiles += Join-Path $outputDir ("${baseName}_split_$($StartNumber + $segmentIndex)$extension")
        }
    }
    else {
        for ($segmentIndex = 0; $segmentIndex -le $sortedTimes.Count; $segmentIndex++) {
            $finalFiles += Join-Path $outputDir ("${baseName}_split_$($StartNumber + $segmentIndex)$extension")
        }
    }

    $tempDir = $null
    if ($onlyInner) {
        $tempDir = Join-Path $outputDir ('.split-video-' + [guid]::NewGuid().ToString('N'))
        $safeTempDir = $tempDir -replace '%', '%%'
        $outputPattern = Join-Path $safeTempDir ('segment_%d' + $extension)
        $segmentStartNumber = 0
    }
    else {
        $outputPattern = Join-Path $safeOutputDir ("${safeBaseName}_split_%d$extension")
        $segmentStartNumber = $StartNumber
    }

    $ffmpegOutputFiles = @()
    if ($onlyInner) {
        for ($segmentIndex = 0; $segmentIndex -le $sortedTimes.Count; $segmentIndex++) {
            $ffmpegOutputFiles += Join-Path $tempDir ("segment_$segmentIndex$extension")
        }
    }
    else {
        $ffmpegOutputFiles = @($finalFiles)
    }

    $existingFiles = @($finalFiles | Where-Object { Test-Path -LiteralPath $_ })
    if ($existingFiles.Count -gt 0 -and -not $Overwrite) {
        throw "Output files already exist: $($existingFiles -join ', '). Use -Overwrite to replace them."
    }

    $ffmpeg = Resolve-Executable -NameOrPath $FFmpegPath -DisplayName 'ffmpeg'
    $argumentList = [System.Collections.Generic.List[string]]::new()

    function Add-Argument {
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$Value
        )
        [void]$argumentList.Add($Value)
    }

    Add-Argument '-hide_banner'
    Add-Argument '-nostdin'
    Add-Argument '-loglevel'
    Add-Argument $LogLevel
    Add-Argument '-nostats'
    Add-Argument '-progress'
    Add-Argument 'pipe:1'
    if ($Overwrite) {
        Add-Argument '-y'
    }
    else {
        Add-Argument '-n'
    }
    Add-Argument '-i'
    Add-Argument $inputFull
    Add-Argument '-map'
    Add-Argument '0'
    Add-Argument '-c'
    Add-Argument 'copy'
    Add-Argument '-f'
    Add-Argument 'segment'

    $segmentTimesValue = (($sortedTimes | ForEach-Object {
        $_.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
    }) -join ',')
    Add-Argument '-segment_times'
    Add-Argument $segmentTimesValue
    Add-Argument '-reset_timestamps'
    Add-Argument '1'
    Add-Argument '-segment_start_number'
    Add-Argument ([string]$segmentStartNumber)

    if ($ExtraFFmpegArgs -and $ExtraFFmpegArgs.Count -gt 0) {
        foreach ($extraArg in $ExtraFFmpegArgs) {
            Add-Argument $extraArg
        }
    }

    Add-Argument $outputPattern

    $logFull = $null
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $logFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)
        if ($logFull -eq $inputFull -or $finalFiles -contains $logFull -or $ffmpegOutputFiles -contains $logFull) {
            throw 'LogPath must be different from InputPath and the output files.'
        }
        if (Test-Path -LiteralPath $logFull -PathType Container) {
            throw "LogPath is a directory: $logFull"
        }
    }

    $ffmpegArgArray = $argumentList.ToArray()
    $displayCommand = "$ffmpeg " + (($ffmpegArgArray | ForEach-Object { Format-ProcessArgument -Argument $_ }) -join ' ')

    $expectedOutputInfo = foreach ($file in $finalFiles) {
        [pscustomobject]@{
            Path      = $file
            SizeBytes = $null
        }
    }

    $resultBase = [ordered]@{
        InputPath       = $inputFull
        OutputDirectory = $outputDir
        SplitPoints     = @($sortedTimes)
        OnlyInner       = $onlyInner
        OutputFiles     = @($expectedOutputInfo)
        CommandLine     = $displayCommand
    }

    if ($DryRun) {
        $resultBase.Success = $true
        $resultBase.DryRun = $true
        $resultBase.ExitCode = $null
        return [pscustomobject]$resultBase
    }

    if (-not $PSCmdlet.ShouldProcess($outputDir, "Split video into $($finalFiles.Count) part(s)")) {
        $resultBase.Success = $true
        $resultBase.Skipped = $true
        $resultBase.ExitCode = $null
        return [pscustomobject]$resultBase
    }

    if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    if ($onlyInner) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }
    if ($logFull) {
        $logDirectory = [IO.Path]::GetDirectoryName($logFull)
        if ($logDirectory -and -not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        }
    }

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $processResult = Invoke-FFmpegProcess `
            -FFmpegPath $ffmpeg `
            -ArgumentList $ffmpegArgArray `
            -ShowProgress (-not $NoProgress.IsPresent) `
            -VerboseOutput ($VerbosePreference -ne 'SilentlyContinue')
        $ffmpegOutput = $processResult.LogLines
        $exitCode = $processResult.ExitCode
    }
    finally {
        $stopwatch.Stop()
    }

    $logText = ($ffmpegOutput -join [Environment]::NewLine).TrimEnd()
    if ($logFull) {
        [IO.File]::WriteAllText($logFull, $logText, [Text.UTF8Encoding]::new($false))
    }

    if ($exitCode -ne 0) {
        $tail = ($ffmpegOutput | Select-Object -Last 30) -join [Environment]::NewLine
        $tempMessage = if ($onlyInner -and (Test-Path -LiteralPath $tempDir)) {
            "`nTemporary segments were kept in: $tempDir"
        }
        else {
            ''
        }
        throw "ffmpeg failed with exit code $exitCode.`n$tail$tempMessage"
    }

    $missingFiles = @($ffmpegOutputFiles | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missingFiles.Count -gt 0) {
        $actualFiles = @($ffmpegOutputFiles | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
        $producedDir = if ($onlyInner) { $tempDir } else { $outputDir }
        $message = "ffmpeg produced fewer segments than requested (expected $($ffmpegOutputFiles.Count), found $($actualFiles.Count)). " +
            'This usually happens with -c copy when a requested split point cannot be aligned to a keyframe. ' +
            'Move the split points or re-encode for exact cuts. ' +
            "Missing: $($missingFiles -join ', '). " +
            "Produced files were kept in: $producedDir"
        throw $message
    }

    if ($onlyInner) {
        try {
            for ($segmentIndex = 1; $segmentIndex -le ($sortedTimes.Count - 1); $segmentIndex++) {
                $sourceFile = Join-Path $tempDir ("segment_$segmentIndex$extension")
                $targetFile = $finalFiles[$segmentIndex - 1]
                Move-Item -LiteralPath $sourceFile -Destination $targetFile -Force
            }
        }
        catch {
            throw "Failed to move inner segments to the output directory. Temporary files were kept in '$tempDir'. $($_.Exception.Message)"
        }

        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $outputInfo = foreach ($file in $finalFiles) {
        $outputItem = Get-Item -LiteralPath $file
        [pscustomobject]@{
            Path      = $outputItem.FullName
            SizeBytes = $outputItem.Length
        }
    }

    [pscustomobject]@{
        InputPath       = $inputFull
        OutputDirectory = $outputDir
        SplitPoints     = @($sortedTimes)
        OnlyInner       = $onlyInner
        OutputFiles     = @($outputInfo)
        Success         = $true
        ExitCode        = 0
        Elapsed         = $stopwatch.Elapsed
        CommandLine     = $displayCommand
        LogPath         = $logFull
    }
}

Export-ModuleMember -Function Invoke-VideoRender, Split-Video, Test-RenderEnvironment, Get-VideoInfo
