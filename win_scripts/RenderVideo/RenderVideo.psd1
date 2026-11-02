@{
    RootModule           = 'RenderVideo.psm1'
    ModuleVersion        = '1.3.0'
    GUID                 = 'da88d6f2-0942-4d52-b4ab-13ae9d69b7c4'
    Author               = 'Vicat'
    CompanyName          = ''
    Copyright            = '(c) 2026 Vicat. All rights reserved.'
    Description          = '纯 ffmpeg 视频编码/拆分库，不依赖 Redis / 微信 / 上传队列。'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @('Invoke-VideoRender', 'Split-Video', 'Test-RenderEnvironment', 'Get-VideoInfo')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('ffmpeg', 'video', 'render', 'nvenc')
            ProjectUri   = ''
            ReleaseNotes = 'Add Split-Video -OnlyInner for inner time ranges.'
        }
    }
}
