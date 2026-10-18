<#
  管理"开机自启"：往「启动」文件夹放一个指向 powershell.exe 的快捷方式。
  不经过 wscript / .vbs（那台机器上 .vbs 关联坏了，wscript 一跑就报错）。

  用法：
    powershell -ExecutionPolicy Bypass -File autostart.ps1 status
    powershell -ExecutionPolicy Bypass -File autostart.ps1 enable
    powershell -ExecutionPolicy Bypass -File autostart.ps1 disable

  点桌面上的「开机自启-开启.cmd / 关闭.cmd」效果相同。
#>
param([ValidateSet('enable', 'disable', 'status')][string]$Action = 'status')

$ErrorActionPreference = 'Stop'

$Root     = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
$Ps1      = Join-Path $Root 'orb.ps1'
$Ico      = Join-Path $Root 'assets\orb.ico'
$Startup  = Join-Path ([Environment]::GetFolderPath('Startup')) 'DeepSeek 悬浮球.lnk'
$RunKey   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunValue = 'DeepSeekOrb'
$LnkArgs  = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $Ps1 + '"'

function Get-RunValue {
    try { return (Get-ItemProperty -Path $RunKey -Name $RunValue -ErrorAction SilentlyContinue).$RunValue }
    catch { return $null }
}

function Show-Status {
    $lnk = Test-Path -LiteralPath $Startup
    $run = Get-RunValue
    Write-Host ''
    Write-Host 'DeepSeek 悬浮球 · 开机自启状态' -ForegroundColor Cyan
    Write-Host ("  启动文件夹快捷方式 : " + $(if ($lnk) { '有  -> ' + $Startup } else { '无' }))
    Write-Host ("  注册表 Run 项      : " + $(if ($run) { $run } else { '无' }))
    Write-Host ('  结论               : ' + $(if ($lnk -or $run) { '已开启' } else { '未开启' }))
    if ($run -and ($run -like '*.vbs*')) {
        Write-Host '  注意：这是旧版 wscript/.vbs 自启项，会开机报错，执行 enable 可迁移。' -ForegroundColor Yellow
    }
    Write-Host ''
}

switch ($Action) {
    'status' { Show-Status }

    'enable' {
        if (-not (Test-Path -LiteralPath $Ps1)) { Write-Host "找不到 orb.ps1: $Ps1" -ForegroundColor Red; exit 1 }
        $ws  = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut($Startup)
        $lnk.TargetPath       = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $lnk.Arguments        = $LnkArgs
        $lnk.WorkingDirectory = $Root
        if (Test-Path -LiteralPath $Ico) { $lnk.IconLocation = "$Ico,0" }
        $lnk.Description = 'DeepSeek 悬浮球'
        $lnk.WindowStyle = 7
        $lnk.Save()
        try { Remove-ItemProperty -Path $RunKey -Name $RunValue -ErrorAction SilentlyContinue } catch {}
        Write-Host '已开启：登录时自动启动（启动文件夹快捷方式）。' -ForegroundColor Green
        Show-Status
    }

    'disable' {
        if (Test-Path -LiteralPath $Startup) { Remove-Item -LiteralPath $Startup -Force }
        try { Remove-ItemProperty -Path $RunKey -Name $RunValue -ErrorAction SilentlyContinue } catch {}
        Write-Host '已关闭开机自启（快捷方式和注册表项都清掉了）。' -ForegroundColor Green
        Show-Status
    }
}
