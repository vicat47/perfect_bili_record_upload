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

        [ValidateRange(1, 65535)]
        [int]$RedisPort = 6379,

        [ValidateRange(0, 15)]
        [int]$RedisDatabase = 0,

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

    $redisArgs = @('-h', $RedisHost, '-p', [string]$RedisPort)
    if ($RedisDatabase -ne 0) {
        $redisArgs += @('-n', [string]$RedisDatabase)
    }
    $redisArgs += @('--raw')

    $oldOutputEncoding = $OutputEncoding
    $oldConsoleEncoding = $null
    try {
        $OutputEncoding = [Text.UTF8Encoding]::new($false)
        try {
            $oldConsoleEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        }
        catch {
            $oldConsoleEncoding = $null
        }

        if ($PSBoundParameters.ContainsKey('InputValue')) {
            $redisArgs += @('-x')
            $output = $InputValue | & $redisCli @redisArgs @Arguments
        }
        else {
            $output = & $redisCli @redisArgs @Arguments
        }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $OutputEncoding = $oldOutputEncoding
        if ($null -ne $oldConsoleEncoding) {
            try {
                [Console]::OutputEncoding = $oldConsoleEncoding
            }
            catch {
            }
        }
    }

    if ($exitCode -ne 0) {
        throw "redis-cli failed with exit code $exitCode (host: $RedisHost, command: $($Arguments -join ' '))."
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

function Resolve-UploadQueueFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        throw 'Cannot resolve an upload file from a null input object.'
    }

    if ($InputObject -is [string]) {
        if ([string]::IsNullOrWhiteSpace($InputObject)) {
            throw 'Cannot resolve an upload file from an empty path.'
        }
        return $InputObject
    }

    if ($InputObject -is [IO.FileInfo]) {
        return $InputObject.FullName
    }

    if ($InputObject -is [IO.DirectoryInfo]) {
        throw "Directory input is not supported: $($InputObject.FullName)"
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in @('OutputFiles', 'OutputPath', 'Path', 'FullName')) {
            if ($InputObject.Contains($key)) {
                Resolve-UploadQueueFilePath -InputObject $InputObject[$key]
                return
            }
        }
        throw 'Cannot resolve an upload file from the dictionary input. Expected OutputFiles, OutputPath, Path, or FullName.'
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        foreach ($item in $InputObject) {
            Resolve-UploadQueueFilePath -InputObject $item
        }
        return
    }

    $properties = $InputObject.PSObject.Properties
    foreach ($propertyName in @('OutputFiles', 'OutputPath', 'Path', 'FullName')) {
        if ($properties[$propertyName]) {
            Resolve-UploadQueueFilePath -InputObject $properties[$propertyName].Value
            return
        }
    }

    throw "Cannot resolve an upload file from input object of type '$($InputObject.GetType().FullName)'. Expected Split-Video/Invoke-VideoRender output, FileInfo, or a path string."
}

function Add-UploadQueue {
    <#
    .SYNOPSIS
        把渲染/拆分产物加入 Redis 上传队列。

    .DESCRIPTION
        每个文件生成一条 JSON，按输入顺序 RPUSH 到上传队列。
        支持管道输入：
            Split-Video ... | Add-UploadQueue -Bvid BV... -RedisHost 192.168.31.40
            Invoke-VideoRender ... | Add-UploadQueue -Bvid BV... -RedisHost 192.168.31.40
            Get-ChildItem ... | Add-UploadQueue -Bvid BV... -RedisHost 192.168.31.40

        默认不输出结果；加 -PassThru 返回每条队列项。
        加 -WhatIf 只显示将要写入的队列项，不连接 Redis。

    .PARAMETER InputObject
        Split-Video / Invoke-VideoRender 的返回对象、FileInfo、路径字符串，或这些对象的数组。

    .PARAMETER Bvid
        上传目标视频的 bvid。上传 worker 会执行 biliup append --vid <bvid> <filename>。

    .PARAMETER QueueKey
        Redis 列表键，默认 biliup:render-list。source/拆分文件走 direct flow；
        旧的 biliup:upload-list 只用于输出目录里的渲染 MP4。

    .PARAMETER RedisHost
        Redis 主机，默认取 $env:REDIS_HOST，否则 127.0.0.1。

    .PARAMETER RedisPort
        Redis 端口，默认 6379。

    .PARAMETER RedisDatabase
        Redis 数据库编号，默认 0。

    .PARAMETER RedisCliPath
        redis-cli 路径，默认 redis-cli。密码可通过 REDISCLI_AUTH 环境变量传入。

    .PARAMETER FileNameStyle
        filename 字段使用文件名（Leaf）还是绝对路径（FullName）。默认 Leaf。
        当前 NAS 上的 Node-RED 上传流程只接受文件名，不能带 X:\ 这样的路径。
        队列项默认只包含 filename 和 bvid；需要附加其他字段时用 -Metadata。

    .PARAMETER Metadata
        额外合并到队列项的字段，例如 @{ title = '...'; tag = '...' }。
        不能覆盖 filename / bvid。

    .PARAMETER PassThru
        输出每条队列项的结果对象。

    .EXAMPLE
        Split-Video .\a.mkv 10:00 20:00 |
            Add-UploadQueue -Bvid BV1xxxxxxxxx -RedisHost 192.168.31.40

    .EXAMPLE
        Invoke-VideoRender -InputPath .\a.mkv -OutputPath .\out\a.mp4 |
            Add-UploadQueue -Bvid BV1xxxxxxxxx -RedisHost 192.168.31.40 -WhatIf -PassThru

    .EXAMPLE
        $result = Split-Video .\a.mkv 10:00 20:00
        $result.OutputFiles | Where-Object SizeBytes -gt 1GB |
            Add-UploadQueue -Bvid BV1xxxxxxxxx -RedisHost 192.168.31.40 -PassThru
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [Alias('Path', 'FullName')]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Bvid,

        [string]$QueueKey = 'biliup:render-list',
        [string]$RedisHost = $(if ($env:REDIS_HOST) { $env:REDIS_HOST } else { '127.0.0.1' }),
        [ValidateRange(1, 65535)]
        [int]$RedisPort = 6379,
        [ValidateRange(0, 15)]
        [int]$RedisDatabase = 0,
        [string]$RedisCliPath = 'redis-cli',
        [ValidateSet('Leaf', 'FullName')]
        [string]$FileNameStyle = 'Leaf',
        [hashtable]$Metadata,
        [switch]$PassThru
    )

    begin {
        if ([string]::IsNullOrWhiteSpace($Bvid)) {
            throw 'Bvid cannot be empty.'
        }
        if ($Bvid -notmatch '^BV[0-9A-Za-z]+$') {
            throw "Invalid Bvid '$Bvid'. Expected BV followed by letters or digits."
        }
        if ([string]::IsNullOrWhiteSpace($QueueKey)) {
            throw 'QueueKey cannot be empty.'
        }
        if ([string]::IsNullOrWhiteSpace($RedisHost)) {
            throw 'RedisHost cannot be empty.'
        }
        if ($Metadata) {
            foreach ($key in $Metadata.Keys) {
                if (@('filename', 'bvid') -contains [string]$key) {
                    throw "Metadata cannot override reserved field '$key'."
                }
            }
        }

        $queued = [System.Collections.Generic.List[object]]::new()
    }

    process {
        $paths = @(Resolve-UploadQueueFilePath -InputObject $InputObject)
        if ($paths.Count -eq 0) {
            throw 'No upload files were found in the input object.'
        }

        foreach ($path in $paths) {
            $item = Get-Item -LiteralPath $path -ErrorAction Stop
            if ($item.PSIsContainer) {
                throw "Upload input is a directory: $($item.FullName)"
            }
            $fullPath = $item.FullName

            $entry = [ordered]@{
                filename = if ($FileNameStyle -eq 'FullName') { $fullPath } else { $item.Name }
                bvid     = $Bvid
            }
            if ($Metadata) {
                foreach ($key in $Metadata.Keys) {
                    $entry[[string]$key] = $Metadata[$key]
                }
            }
            $json = ConvertTo-Json -InputObject $entry -Compress -Depth 10

            $target = "$RedisHost`:$RedisPort/$QueueKey"
            if ($PSCmdlet.ShouldProcess($target, "RPUSH upload item for '$($item.Name)'")) {
                try {
                    $rawLength = Invoke-RedisCli `
                        -RedisHost $RedisHost `
                        -RedisPort $RedisPort `
                        -RedisDatabase $RedisDatabase `
                        -Arguments @('RPUSH', $QueueKey) `
                        -InputValue $json `
                        -RedisCliPath $RedisCliPath
                    $queueLength = 0
                    $lastValue = @($rawLength)[-1]
                    if (-not [int]::TryParse([string]$lastValue, [ref]$queueLength)) {
                        throw "Unexpected redis-cli RPUSH response: $rawLength"
                    }
                }
                catch {
                    $alreadyQueued = if ($queued.Count -gt 0) {
                        "Already queued: " + (($queued | ForEach-Object { $_.Path }) -join ', ') + '.'
                    }
                    else {
                        'No files were queued before this failure.'
                    }
                    throw "Failed to enqueue '$fullPath' to '$QueueKey' on '$RedisHost`:$RedisPort'. $alreadyQueued Payload: $json`n$($_.Exception.Message)"
                }

                $result = [pscustomobject]@{
                    Path        = $fullPath
                    FileName    = $item.Name
                    QueueKey    = $QueueKey
                    QueueLength = $queueLength
                    Json        = $json
                    Queued      = $true
                    Success     = $true
                }
                [void]$queued.Add($result)
                Write-Verbose "Queued '$fullPath' to '$QueueKey' (list length $queueLength)."
                if ($PassThru) {
                    $result
                }
            }
            elseif ($PassThru) {
                [pscustomobject]@{
                    Path        = $fullPath
                    FileName    = $item.Name
                    QueueKey    = $QueueKey
                    QueueLength = $null
                    Json        = $json
                    Queued      = $false
                    Success     = $true
                }
            }
        }
    }
}

Export-ModuleMember -Function Write-PipelineLog, Send-WechatMessage, Send-PipelineNotification, Invoke-RedisCli, Add-UploadQueue
