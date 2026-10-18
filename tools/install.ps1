<#
  安装：在桌面创建「DeepSeek 悬浮球」快捷方式（直接调用 powershell.exe 运行 orb.ps1）。
  不写注册表、不需要管理员权限、不经过 wscript / .vbs。
#>
$ErrorActionPreference = 'Stop'

$Root    = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
$Ps1     = Join-Path $Root 'orb.ps1'
$Ico     = Join-Path $Root 'assets\orb.ico'
$Desktop = [Environment]::GetFolderPath('Desktop')
$Lnk     = Join-Path $Desktop 'DeepSeek 悬浮球.lnk'
$LnkArgs = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $Ps1 + '"'

if (-not (Test-Path -LiteralPath $Ps1)) {
    Write-Host "找不到 orb.ps1：$Ps1" -ForegroundColor Red
    exit 1
}

$ws = New-Object -ComObject WScript.Shell
$s  = $ws.CreateShortcut($Lnk)
$s.TargetPath       = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$s.Arguments        = $LnkArgs
$s.WorkingDirectory = $Root
if (Test-Path -LiteralPath $Ico) { $s.IconLocation = "$Ico,0" }
$s.Description = 'DeepSeek 悬浮球'
$s.WindowStyle = 7
$s.Save()

Write-Host ''
Write-Host '[OK] 已在桌面创建快捷方式：' -ForegroundColor Green
Write-Host "     $Lnk"
Write-Host ''
Write-Host '下一步：'
Write-Host '  1. 双击桌面上的「DeepSeek 悬浮球」'
Write-Host '  2. 点右下角那颗蓝球 -> 在弹出的窗口里登录 DeepSeek（只需一次）'
Write-Host '  3. Ctrl+Alt+D 可随时开合面板'
Write-Host ''
Write-Host '想开机自启：双击本目录的「开机自启-开启.cmd」'
Write-Host ''
