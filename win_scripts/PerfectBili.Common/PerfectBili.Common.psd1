@{
    RootModule        = 'PerfectBili.Common.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '155bdbe4-595f-48bc-b7b9-e15c1c7eea14'
    Author            = 'Vicat'
    CompanyName       = ''
    Copyright         = '(c) 2026 Vicat. All rights reserved.'
    Description       = 'perfect_bili_record_upload 的公共日志、通知和 Redis 辅助函数。'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Write-PipelineLog', 'Send-WechatMessage', 'Send-PipelineNotification', 'Invoke-RedisCli')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('bilibili', 'obs', 'redis', 'powershell')
        }
    }
}
