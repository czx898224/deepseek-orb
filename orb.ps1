<#
  DeepSeek 悬浮球  v1.0
  ------------------------------------------------------------------
  · 通体蓝色圆球（分层窗口，逐像素透明 / 柔和投影）
  · 单击球 = 开合面板；拖动球 = 挪位置（自动记忆）；右键 = 菜单
  · 面板 = Edge 应用窗，加载 chat.deepseek.com，独立 profile 持久登录
  · Ctrl+Alt+D 全局热键；全屏游戏自动隐藏；游戏模式更小更淡
  · 只用标准 Win32 置顶窗口，不注入、不挂钩任何游戏进程
#>
param([switch]$SelfTest, [switch]$PanelTest)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:Root       = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:AssetPng   = Join-Path $script:Root 'assets\orb.png'
$script:ConfigPath = Join-Path $script:Root 'config.json'
$script:LogPath    = Join-Path $script:Root 'orb.log'
$script:ProfileDir = Join-Path $env:LOCALAPPDATA 'DeepSeekOrb\edge-profile'
$script:EdgeExe    = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
$script:BallRatio  = 0.725

function Write-Log([string]$m) {
    try { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Out-File -LiteralPath $script:LogPath -Append -Encoding utf8 } catch {}
}

function Save-Shot([int]$x, [int]$y, [int]$w, [int]$h, [string]$path) {
    try {
        $bmp = [System.Drawing.Bitmap]::new($w, $h)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try { $g.CopyFromScreen($x, $y, 0, 0, [System.Drawing.Size]::new($w, $h)) }
        catch { Write-Log "截图失败: $($_.Exception.Message)" }
        $g.Dispose()
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    } catch { Write-Log "截图异常: $($_.Exception.Message)" }
}

# =====================================================================
#  Win32 / GDI 封装
# =====================================================================
$cs = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public static class OrbNative
{
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct SIZE { public int cx, cy; }
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct BLENDFUNCTION { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }
    [StructLayout(LayoutKind.Sequential)]
    public struct BITMAPINFO
    {
        public int biSize, biWidth, biHeight;
        public short biPlanes, biBitCount;
        public int biCompression, biSizeImage, biXPelsPerMeter, biYPelsPerMeter, biClrUsed, biClrImportant;
    }

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int idx, int val);
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h, int id, uint mod, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr h, int id);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern uint GetDpiForSystem();
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int v);
    [DllImport("shcore.dll")] public static extern int SHQueryUserNotificationState(out int state);
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);

    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")]
    static extern IntPtr CreateDIBSection(IntPtr dc, ref BITMAPINFO bmi, uint usage, out IntPtr bits, IntPtr section, uint offset);
    [DllImport("user32.dll")]
    static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr dstDc, ref POINT dst, ref SIZE size,
                                           IntPtr srcDc, ref POINT src, int colorKey, ref BLENDFUNCTION blend, int flags);

    const int GWL_EXSTYLE = -20;
    const int GWL_STYLE = -16;
    const int WS_EX_LAYERED = 0x00080000;
    const int WS_EX_TOOLWINDOW = 0x00000080;
    const int WS_EX_APPWINDOW = 0x00040000;
    const int WS_CAPTION = 0x00C00000;
    const int WS_THICKFRAME = 0x00040000;
    const int WS_MINIMIZEBOX = 0x00020000;
    const int WS_MAXIMIZEBOX = 0x00010000;
    const int WS_SYSMENU = 0x00080000;
    const int WS_POPUP = unchecked((int)0x80000000);
    const int WS_VISIBLE = 0x10000000;

    public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    public const uint SWP_NOSIZE = 0x0001, SWP_NOMOVE = 0x0002, SWP_NOZORDER = 0x0004,
                      SWP_NOACTIVATE = 0x0010, SWP_FRAMECHANGED = 0x0020, SWP_SHOWWINDOW = 0x0040;
    public const int SW_HIDE = 0, SW_SHOWNOACTIVATE = 4, SW_SHOW = 5;

    public static void MakeLayeredToolWindow(IntPtr h)
    {
        int ex = GetWindowLong(h, GWL_EXSTYLE);
        ex = (ex | WS_EX_LAYERED | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
        SetWindowLong(h, GWL_EXSTYLE, ex);
    }

    public static bool Blit(IntPtr hwnd, Bitmap src, int x, int y, byte constAlpha)
    {
        int w = src.Width, h = src.Height;
        byte[] buf = new byte[w * h * 4];
        BitmapData bd = src.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try { Marshal.Copy(bd.Scan0, buf, 0, buf.Length); }
        finally { src.UnlockBits(bd); }

        for (int i = 0; i < buf.Length; i += 4)
        {
            int a = buf[i + 3];
            if (a != 255)
            {
                buf[i]     = (byte)(buf[i]     * a / 255);
                buf[i + 1] = (byte)(buf[i + 1] * a / 255);
                buf[i + 2] = (byte)(buf[i + 2] * a / 255);
            }
        }

        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memDc = CreateCompatibleDC(screenDc);
        BITMAPINFO bmi = new BITMAPINFO();
        bmi.biSize = Marshal.SizeOf(typeof(BITMAPINFO));
        bmi.biWidth = w;
        bmi.biHeight = -h;
        bmi.biPlanes = 1;
        bmi.biBitCount = 32;
        IntPtr bits;
        IntPtr hbmp = CreateDIBSection(memDc, ref bmi, 0, out bits, IntPtr.Zero, 0);
        if (hbmp == IntPtr.Zero) { DeleteDC(memDc); ReleaseDC(IntPtr.Zero, screenDc); return false; }

        Marshal.Copy(buf, 0, bits, buf.Length);
        IntPtr old = SelectObject(memDc, hbmp);

        BLENDFUNCTION bf = new BLENDFUNCTION();
        bf.BlendOp = 0;
        bf.SourceConstantAlpha = constAlpha;
        bf.AlphaFormat = 1;
        SIZE size = new SIZE(); size.cx = w; size.cy = h;
        POINT pd = new POINT(); pd.X = x; pd.Y = y;
        POINT ps = new POINT();

        bool ok = UpdateLayeredWindow(hwnd, screenDc, ref pd, ref size, memDc, ref ps, 0, ref bf, 2);

        SelectObject(memDc, old);
        DeleteObject(hbmp);
        DeleteDC(memDc);
        ReleaseDC(IntPtr.Zero, screenDc);
        return ok;
    }

    public static void SetFrameless(IntPtr h, bool on)
    {
        int style = GetWindowLong(h, GWL_STYLE);
        if (on)
        {
            style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
            style |= WS_POPUP | WS_VISIBLE;
        }
        else
        {
            style &= ~WS_POPUP;
            style |= WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU | WS_VISIBLE;
        }
        SetWindowLong(h, GWL_STYLE, style);
        SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
    }

    public static void RoundCorners(IntPtr h)
    {
        try { int pref = 2; DwmSetWindowAttribute(h, 33, ref pref, 4); } catch { }
    }

    public static IntPtr FindChromeWindow(int[] pids, bool requireVisible)
    {
        IntPtr best = IntPtr.Zero;
        int bestArea = 0;
        EnumWindowsProc cb = delegate(IntPtr h, IntPtr l)
        {
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            bool match = false;
            for (int i = 0; i < pids.Length; i++) if (pids[i] == (int)pid) { match = true; break; }
            if (!match) return true;
            StringBuilder sb = new StringBuilder(256);
            GetClassName(h, sb, 256);
            if (sb.ToString() != "Chrome_WidgetWin_1") return true;
            if (requireVisible && !IsWindowVisible(h)) return true;
            RECT r;
            if (!GetWindowRect(h, out r)) return true;
            int area = (r.Right - r.Left) * (r.Bottom - r.Top);
            if (area > bestArea) { bestArea = area; best = h; }
            return true;
        };
        EnumWindows(cb, IntPtr.Zero);
        return best;
    }

    public static int GetPidOfWindow(IntPtr h)
    {
        uint pid;
        GetWindowThreadProcessId(h, out pid);
        return (int)pid;
    }

    /// 按"目标矩形"反查 Chrome 风格窗口（CIM 不可用时的兜底）
    public static IntPtr FindChromeWindowByRect(int x, int y, int w, int h, int tol)
    {
        IntPtr best = IntPtr.Zero;
        int bestScore = int.MaxValue;
        EnumWindowsProc cb = delegate(IntPtr hh, IntPtr l)
        {
            StringBuilder sb = new StringBuilder(256);
            GetClassName(hh, sb, 256);
            if (sb.ToString() != "Chrome_WidgetWin_1") return true;
            if (!IsWindowVisible(hh)) return true;
            RECT r;
            if (!GetWindowRect(hh, out r)) return true;
            int dx = Math.Abs(r.Left - x), dy = Math.Abs(r.Top - y);
            int dw = Math.Abs((r.Right - r.Left) - w), dh = Math.Abs((r.Bottom - r.Top) - h);
            int score = dx + dy + dw + dh;
            if (dx <= tol && dy <= tol && dw <= tol && dh <= tol && score < bestScore)
            { bestScore = score; best = hh; }
            return true;
        };
        EnumWindows(cb, IntPtr.Zero);
        return best;
    }

    public static bool IsFullscreenApp()
    {
        int st = 0;
        try { SHQueryUserNotificationState(out st); } catch { return false; }
        return st == 2 || st == 3;
    }

    public static RECT GetRect(IntPtr h)
    {
        RECT r;
        GetWindowRect(h, out r);
        return r;
    }
}

public class HotkeyFilter : IMessageFilter
{
    public event EventHandler Pressed;
    public bool PreFilterMessage(ref Message m)
    {
        if (m.Msg == 0x0312)
        {
            EventHandler h = Pressed;
            if (h != null) { h(null, EventArgs.Empty); return true; }
        }
        return false;
    }
}
'@

Add-Type -TypeDefinition $cs -ReferencedAssemblies System.Windows.Forms, System.Drawing

# =====================================================================
#  单实例
# =====================================================================
$mutex = [System.Threading.Mutex]::new($false, 'Local\DeepSeekOrbSingleton')
if (-not $mutex.WaitOne(0)) { Write-Log '已有实例在运行，退出。'; return }

# =====================================================================
#  DPI
# =====================================================================
try { [void][OrbNative]::SetProcessDpiAwareness(1) }
catch { try { [void][OrbNative]::SetProcessDPIAware() } catch {} }

$script:Scale = 1.0
try {
    $dpi = [OrbNative]::GetDpiForSystem()
    if ($dpi -gt 0) { $script:Scale = [double]$dpi / 96.0 }
} catch { $script:Scale = 1.0 }
if ($script:Scale -le 0) { $script:Scale = 1.0 }

function SD([double]$dip) { return [int][math]::Round($dip * $script:Scale) }

# =====================================================================
#  配置
# =====================================================================
$script:Cfg = [ordered]@{
    url              = 'https://chat.deepseek.com/'
    widthDip         = 300
    heightDip        = 350
    orbDip           = 34
    hotkey           = 'Ctrl+Alt+D'
    frameless        = $false
    hideOnFullscreen = $true
    gameMode         = $false
    orbX             = -1
    orbY             = -1
}

function Import-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) { return }
    try {
        $j = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in @($script:Cfg.Keys)) {
            if ($null -ne $j.PSObject.Properties[$k]) { $script:Cfg[$k] = $j.$k }
        }
    } catch { Write-Log "读配置失败: $($_.Exception.Message)" }
}

function Export-Config {
    try { ($script:Cfg | ConvertTo-Json -Depth 4) | Out-File -LiteralPath $script:ConfigPath -Encoding UTF8 }
    catch { Write-Log "写配置失败: $($_.Exception.Message)" }
}

Import-Config

# 测试/调试用覆盖
if ($env:DSH_ORB_PROFILE)   { $script:ProfileDir = $env:DSH_ORB_PROFILE }
if ($env:DSH_ORB_URL)       { $script:Cfg.url = $env:DSH_ORB_URL }
if ($env:DSH_ORB_FRAMELESS) { $script:Cfg.frameless = ($env:DSH_ORB_FRAMELESS -eq '1') }

function Parse-Hotkey([string]$s) {
    $mods = 0; $vk = 0
    foreach ($raw in ($s -split '\+')) {
        $p = $raw.Trim()
        if ($p -eq '') { continue }
        $low = $p.ToLowerInvariant()
        if     ($low -eq 'ctrl' -or $low -eq 'control') { $mods = $mods -bor 0x0002 }
        elseif ($low -eq 'alt')                         { $mods = $mods -bor 0x0001 }
        elseif ($low -eq 'shift')                       { $mods = $mods -bor 0x0004 }
        elseif ($low -eq 'win')                         { $mods = $mods -bor 0x0008 }
        elseif ($p -match '^[Ff]([1-9]|1[0-2])$')       { $vk = 0x6F + [int]$Matches[1] }
        elseif ($p.Length -eq 1) {
            $c = $p.ToUpperInvariant()
            if ($c -match '^[A-Z0-9]$') { $vk = [int][char]$c }
            elseif ($p -eq '`' -or $p -eq '~') { $vk = 0xC0 }
            elseif ($p -eq '-') { $vk = 0xBD }
            elseif ($p -eq '=') { $vk = 0xBB }
            elseif ($p -eq '/') { $vk = 0xBF }
            elseif ($p -eq ';') { $vk = 0xBA }
            elseif ($p -eq "'") { $vk = 0xDE }
            elseif ($p -eq ',') { $vk = 0xBC }
            elseif ($p -eq '.') { $vk = 0xBE }
        }
        elseif ($low -eq 'space') { $vk = 0x20 }
        elseif ($low -eq 'tab')   { $vk = 0x09 }
    }
    if ($vk -eq 0) { $mods = 0x0003; $vk = 0x44 }
    return @($mods, $vk)
}

$hk = Parse-Hotkey $script:Cfg.hotkey
$script:HotkeyMods = [uint32]$hk[0]
$script:HotkeyVk   = [uint32]$hk[1]
$script:HotkeyId   = 0xD5E1

# =====================================================================
#  面板（Edge 应用窗）
# =====================================================================
$script:PanelHwnd   = [IntPtr]::Zero
$script:PanelPid    = 0
$script:LaunchedPid = 0
$script:PanelOpen   = $false
$script:Busy        = $false
$script:EdgePids    = @()

function Find-EdgeExe {
    $cands = @(
        'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
        'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe')
    )
    foreach ($c in $cands) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
    try {
        $p = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe' -ErrorAction Stop).'(default)'
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    } catch {}
    return $script:EdgeExe
}

function Get-EdgePids {
    $out = @()
    try {
        $out = @(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" -ErrorAction Stop |
                 Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($script:ProfileDir, [StringComparison]::OrdinalIgnoreCase) -ge 0 } |
                 ForEach-Object { [int]$_.ProcessId })
    } catch { }
    return $out
}

function Find-PanelWindow([int[]]$target) {
    # 1) 刚启动的浏览器进程自己就持有窗口
    if ($script:LaunchedPid -gt 0) {
        for ($i = 0; $i -lt 42; $i++) {
            [System.Windows.Forms.Application]::DoEvents()
            $p = Get-Process -Id $script:LaunchedPid -ErrorAction SilentlyContinue
            if ($p) {
                $h = $p.MainWindowHandle
                if (($h -ne [IntPtr]::Zero) -and [OrbNative]::IsWindow($h)) { return $h }
            }
            Start-Sleep -Milliseconds 150
        }
    }
    # 2) 按命令行里的独立 profile 匹配（桌面环境可用）
    $pids = Get-EdgePids
    if ($pids.Count -gt 0) {
        for ($i = 0; $i -lt 12; $i++) {
            [System.Windows.Forms.Application]::DoEvents()
            $h = [OrbNative]::FindChromeWindow([int[]]$pids, $false)
            if ($h -ne [IntPtr]::Zero) { return $h }
            Start-Sleep -Milliseconds 200
        }
    }
    # 3) 按目标矩形兜底
    for ($i = 0; $i -lt 25; $i++) {
        [System.Windows.Forms.Application]::DoEvents()
        $h = [OrbNative]::FindChromeWindowByRect($target[0], $target[1], $target[2], $target[3], 60)
        if ($h -ne [IntPtr]::Zero) { return $h }
        Start-Sleep -Milliseconds 200
    }
    return [IntPtr]::Zero
}

function Get-PanelRect {
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $w  = SD $script:Cfg.widthDip
    $h  = SD $script:Cfg.heightDip
    $g  = SD 10
    $b  = $script:OrbRect
    if (-not $b) { $b = @(($wa.Right - 100), ($wa.Top + [int]($wa.Height * 0.6)), (SD 60), (SD 60)) }
    $cx = $b[0] + [int]($b[2] / 2)
    $cy = $b[1] + [int]($b[3] / 2)
    if ($cx -gt ($wa.Left + [int]($wa.Width / 2))) { $x = $b[0] - $w - $g } else { $x = $b[0] + $b[2] + $g }
    $y = $cy - [int]($h / 2)
    if ($x -lt ($wa.Left + $g)) { $x = $wa.Left + $g }
    if (($x + $w) -gt ($wa.Right - $g)) { $x = $wa.Right - $g - $w }
    if ($y -lt ($wa.Top + $g)) { $y = $wa.Top + $g }
    if (($y + $h) -gt ($wa.Bottom - $g)) { $y = $wa.Bottom - $g - $h }
    return @([int]$x, [int]$y, [int]$w, [int]$h)
}

function Start-Panel {
    if (-not (Test-Path -LiteralPath $script:EdgeExe)) {
        [void][System.Windows.Forms.MessageBox]::Show("找不到 Microsoft Edge：`r`n$($script:EdgeExe)", 'DeepSeek 悬浮球')
        return $false
    }
    New-Item -ItemType Directory -Force -Path $script:ProfileDir | Out-Null
    $r  = Get-PanelRect
    $lx = [int]($r[0] / $script:Scale)
    $ly = [int]($r[1] / $script:Scale)
    $args = @(
        "--app=$($script:Cfg.url)",
        "--user-data-dir=$($script:ProfileDir)",
        '--no-first-run',
        '--no-default-browser-check',
        "--window-size=$($script:Cfg.widthDip),$($script:Cfg.heightDip)",
        "--window-position=$lx,$ly"
    )
    try {
        $proc = Start-Process -FilePath $script:EdgeExe -ArgumentList $args -PassThru
        $script:LaunchedPid = [int]$proc.Id
    }
    catch { Write-Log "启动 Edge 失败: $($_.Exception.Message)"; return $false }

    $h = Find-PanelWindow $r
    if ($h -ne [IntPtr]::Zero) {
        $script:PanelHwnd = $h
        $script:PanelPid  = [OrbNative]::GetPidOfWindow($h)
        Write-Log "面板窗口句柄: $h  pid: $($script:PanelPid)"
        return $true
    }
    Write-Log '等待 Edge 窗口超时'
    return $false
}

function Show-Panel {
    if (($script:PanelHwnd -ne [IntPtr]::Zero) -and (-not [OrbNative]::IsWindow($script:PanelHwnd))) {
        $script:PanelHwnd = [IntPtr]::Zero
    }
    if ($script:PanelHwnd -eq [IntPtr]::Zero) {
        if (-not (Start-Panel)) { return }
    }
    $r = Get-PanelRect
    if ($script:Cfg.frameless) {
        [OrbNative]::SetFrameless($script:PanelHwnd, $true)
        [OrbNative]::RoundCorners($script:PanelHwnd)
    } else {
        [OrbNative]::SetFrameless($script:PanelHwnd, $false)
    }
    [void][OrbNative]::SetWindowPos($script:PanelHwnd, [OrbNative]::HWND_TOPMOST, $r[0], $r[1], $r[2], $r[3], [OrbNative]::SWP_SHOWWINDOW)
    [void][OrbNative]::ShowWindow($script:PanelHwnd, [OrbNative]::SW_SHOW)
    [void][OrbNative]::SetForegroundWindow($script:PanelHwnd)
    $script:PanelOpen = $true
    Update-OrbMenuText
}

function Hide-Panel {
    if (($script:PanelHwnd -ne [IntPtr]::Zero) -and [OrbNative]::IsWindow($script:PanelHwnd)) {
        [void][OrbNative]::ShowWindow($script:PanelHwnd, [OrbNative]::SW_HIDE)
    }
    $script:PanelOpen = $false
    Update-OrbMenuText
}

function Close-PanelApp {
    $victims = @()
    if ($script:PanelHwnd -ne [IntPtr]::Zero -and [OrbNative]::IsWindow($script:PanelHwnd)) {
        $victims += [OrbNative]::GetPidOfWindow($script:PanelHwnd)
    }
    if ($script:PanelPid -gt 0)    { $victims += $script:PanelPid }
    if ($script:LaunchedPid -gt 0) { $victims += $script:LaunchedPid }
    $victims += (Get-EdgePids)
    Hide-Panel
    foreach ($p in ($victims | Sort-Object -Unique)) {
        if ($p -gt 0) { try { Stop-Process -Id $p -Force -ErrorAction Stop } catch {} }
    }
    $script:PanelHwnd   = [IntPtr]::Zero
    $script:PanelPid    = 0
    $script:LaunchedPid = 0
    $script:EdgePids    = @()
}

function Toggle-Panel {
    if ($script:Busy) { return }
    $script:Busy = $true
    try {
        if ($script:PanelOpen) { Hide-Panel } else { Show-Panel }
    }
    catch { Write-Log "切换面板出错: $($_.Exception.Message)" }
    finally { $script:Busy = $false }
}

# =====================================================================
#  悬浮球窗口
# =====================================================================
$script:SrcOrb   = [System.Drawing.Bitmap]::FromFile($script:AssetPng)
$script:OrbBmp   = $null
$script:OrbPx    = 0
$script:OrbAlpha = 215
$script:OrbRect  = $null
$script:HiddenByFullscreen = $false

$form = [System.Windows.Forms.Form]::new()
$form.Text            = 'DeepSeek 悬浮球'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.AutoScaleMode   = [System.Windows.Forms.AutoScaleMode]::None
$form.ShowInTaskbar   = $false
$form.TopMost         = $true
$form.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
$form.ShowIcon        = $false
$form.BackColor       = [System.Drawing.Color]::Black
$form.MinimizeBox     = $false
$form.MaximizeBox     = $false
$form.Size            = [System.Drawing.Size]::new(1, 1)

function Update-OrbSize {
    $d = SD $script:Cfg.orbDip
    if ($script:Cfg.gameMode) { $d = [int]($d * 0.8) }
    $win = [int][math]::Round($d / $script:BallRatio)
    if ($win -lt 12) { $win = 12 }
    if ($win -eq $script:OrbPx) { return }
    if ($script:OrbBmp) { $script:OrbBmp.Dispose() }
    $bmp = [System.Drawing.Bitmap]::new($win, $win)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingMode    = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($script:SrcOrb, [System.Drawing.Rectangle]::new(0, 0, $win, $win))
    $g.Dispose()
    $script:OrbBmp = $bmp
    $script:OrbPx  = $win
}

function Get-OrbPosition {
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $w  = $script:OrbPx
    if (($script:Cfg.orbX -ge 0) -and ($script:Cfg.orbY -ge 0)) {
        $x = [int]$script:Cfg.orbX
        $y = [int]$script:Cfg.orbY
    } else {
        $x = $wa.Right - $w - (SD 6)
        $y = $wa.Top + [int]($wa.Height * 0.60)
    }
    if ($x -lt ($wa.Left - 4)) { $x = $wa.Left - 4 }
    if ($y -lt ($wa.Top - 4))  { $y = $wa.Top - 4 }
    if ($x -gt ($wa.Right - 4))  { $x = $wa.Right - 4 }
    if ($y -gt ($wa.Bottom - 4)) { $y = $wa.Bottom - 4 }
    return @([int]$x, [int]$y)
}

function Paint-Orb {
    $p = Get-OrbPosition
    [void][OrbNative]::SetWindowPos($form.Handle, [OrbNative]::HWND_TOPMOST, $p[0], $p[1], $script:OrbPx, $script:OrbPx,
        ([OrbNative]::SWP_NOACTIVATE -bor [OrbNative]::SWP_SHOWWINDOW))
    $script:OrbRect = @($p[0], $p[1], $script:OrbPx, $script:OrbPx)
    if (-not [OrbNative]::Blit($form.Handle, $script:OrbBmp, $p[0], $p[1], [byte]$script:OrbAlpha)) {
        Write-Log 'UpdateLayeredWindow 失败'
    }
}

function Set-OrbAlpha([int]$a) {
    $script:OrbAlpha = $a
    if ($script:OrbRect) {
        [void][OrbNative]::Blit($form.Handle, $script:OrbBmp, $script:OrbRect[0], $script:OrbRect[1], [byte]$a)
    }
}

# ---------- 拖动 / 点击 ----------
$script:Dragging   = $false
$script:DragStart  = $null
$script:DragOrigin = $null
$script:Moved      = $false

$form.Add_MouseDown({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:Dragging   = $true
        $script:Moved      = $false
        $script:DragStart  = [System.Windows.Forms.Cursor]::Position
        if ($script:OrbRect) { $script:DragOrigin = @($script:OrbRect[0], $script:OrbRect[1]) }
        else { $script:DragOrigin = @($form.Left, $form.Top) }
    }
})

$form.Add_MouseMove({
    if ($script:Dragging) {
        $p  = [System.Windows.Forms.Cursor]::Position
        $dx = $p.X - $script:DragStart.X
        $dy = $p.Y - $script:DragStart.Y
        if (([math]::Abs($dx) + [math]::Abs($dy)) -gt 4) { $script:Moved = $true }
        $nx = $script:DragOrigin[0] + $dx
        $ny = $script:DragOrigin[1] + $dy
        [void][OrbNative]::SetWindowPos($form.Handle, [OrbNative]::HWND_TOPMOST, $nx, $ny, $script:OrbPx, $script:OrbPx,
            ([OrbNative]::SWP_NOACTIVATE -bor [OrbNative]::SWP_SHOWWINDOW))
        $script:OrbRect = @($nx, $ny, $script:OrbPx, $script:OrbPx)
        [void][OrbNative]::Blit($form.Handle, $script:OrbBmp, $nx, $ny, [byte]$script:OrbAlpha)
    }
})

$form.Add_MouseUp({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($script:Dragging -and ($script:Moved -eq $false)) {
            Toggle-Panel
        } elseif ($script:Dragging) {
            if ($script:OrbRect) {
                $script:Cfg.orbX = $script:OrbRect[0]
                $script:Cfg.orbY = $script:OrbRect[1]
            }
            Export-Config
        }
        $script:Dragging = $false
    }
})

$form.Add_MouseEnter({
    if (-not $script:Cfg.gameMode) { Set-OrbAlpha 255 }
    if ($script:Cfg.gameMode)      { Set-OrbAlpha 200 }
})

$form.Add_MouseLeave({
    if (-not $script:Cfg.gameMode) { Set-OrbAlpha 215 }
    if ($script:Cfg.gameMode)      { Set-OrbAlpha 165 }
})

# ---------- 开机自启（启动文件夹快捷方式；不用 wscript / .vbs） ----------
$script:StartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'DeepSeek 悬浮球.lnk'
$script:RunKey     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$script:RunValue   = 'DeepSeekOrb'

function Get-LaunchArgs {
    return '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $script:Root 'orb.ps1') + '"'
}

function Test-Autostart {
    if (Test-Path -LiteralPath $script:StartupLnk) { return $true }
    try {
        $v = (Get-ItemProperty -Path $script:RunKey -Name $script:RunValue -ErrorAction SilentlyContinue).$($script:RunValue)
        return [bool]$v
    } catch { return $false }
}

function Remove-Autostart {
    if (Test-Path -LiteralPath $script:StartupLnk) {
        try { Remove-Item -LiteralPath $script:StartupLnk -Force } catch { Write-Log "删自启快捷方式失败: $($_.Exception.Message)" }
    }
    try { Remove-ItemProperty -Path $script:RunKey -Name $script:RunValue -ErrorAction SilentlyContinue } catch {}
}

function Enable-Autostart {
    try {
        $ws  = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut($script:StartupLnk)
        $lnk.TargetPath       = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $lnk.Arguments        = Get-LaunchArgs
        $lnk.WorkingDirectory = $script:Root
        $ico = Join-Path $script:Root 'assets\orb.ico'
        if (Test-Path -LiteralPath $ico) { $lnk.IconLocation = "$ico,0" }
        $lnk.Description = 'DeepSeek 悬浮球'
        $lnk.WindowStyle = 7
        $lnk.Save()
        try { Remove-ItemProperty -Path $script:RunKey -Name $script:RunValue -ErrorAction SilentlyContinue } catch {}
        Write-Log '自启已开启：启动文件夹快捷方式'
        return $true
    } catch { Write-Log "开启自启失败: $($_.Exception.Message)"; return $false }
}

function Repair-Autostart {
    # 把旧版的 wscript/.vbs 自启项迁移成启动文件夹快捷方式
    try {
        $v = (Get-ItemProperty -Path $script:RunKey -Name $script:RunValue -ErrorAction SilentlyContinue).$($script:RunValue)
        if (-not $v) { return }
        Write-Log "发现旧自启项: $v"
        if (Test-Path -LiteralPath $script:StartupLnk) {
            Remove-ItemProperty -Path $script:RunKey -Name $script:RunValue -ErrorAction SilentlyContinue
            Write-Log '旧自启项已移除'
        } elseif (Enable-Autostart) {
            Write-Log '旧自启项已迁移为启动文件夹快捷方式'
        }
    } catch { Write-Log "自启迁移异常: $($_.Exception.Message)" }
}

# ---------- 右键菜单 ----------
$menu = [System.Windows.Forms.ContextMenuStrip]::new()
$menu.ShowImageMargin = $false

$miToggle = $menu.Items.Add('打开面板')
$miToggle.Add_Click({ Toggle-Panel })

$miSize = [System.Windows.Forms.ToolStripMenuItem]::new('面板尺寸')
[void]$menu.Items.Add($miSize)
$presets = @(
    @{ n = '蓝框 300 × 350'; w = 300; h = 350 },
    @{ n = '舒适 380 × 520'; w = 380; h = 520 },
    @{ n = '大号 460 × 640'; w = 460; h = 640 }
)
foreach ($p in $presets) {
    $item = $miSize.DropDownItems.Add($p.n)
    $item.Tag = $p
    $item.Add_Click({
        $script:Cfg.widthDip  = $this.Tag.w
        $script:Cfg.heightDip = $this.Tag.h
        Export-Config
        if ($script:PanelOpen) {
            Hide-Panel
            Start-Sleep -Milliseconds 60
            Show-Panel
        }
    })
}
[void]$miSize.DropDownItems.Add([System.Windows.Forms.ToolStripSeparator]::new())
$miSizeReset = $miSize.DropDownItems.Add('改回蓝框尺寸')
$miSizeReset.Add_Click({
    $script:Cfg.widthDip = 300; $script:Cfg.heightDip = 350
    Export-Config
    if ($script:PanelOpen) { Hide-Panel; Start-Sleep -Milliseconds 60; Show-Panel }
})

[void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())

$miFrameless = $menu.Items.Add('无边框面板')
$miFrameless.CheckOnClick = $false
$miFrameless.Add_Click({
    $script:Cfg.frameless = -not $script:Cfg.frameless
    Export-Config
    if ($script:PanelOpen) {
        [OrbNative]::SetFrameless($script:PanelHwnd, [bool]$script:Cfg.frameless)
        if ($script:Cfg.frameless) { [OrbNative]::RoundCorners($script:PanelHwnd) }
    }
    Update-OrbMenuText
})

$miGame = $menu.Items.Add('游戏模式')
$miGame.Add_Click({
    $script:Cfg.gameMode = -not $script:Cfg.gameMode
    Export-Config
    $script:OrbPx = 0
    Update-OrbSize
    if ($script:Cfg.gameMode) { $script:OrbAlpha = 165 } else { $script:OrbAlpha = 215 }
    Paint-Orb
    Update-OrbMenuText
})

$miFull = $menu.Items.Add('全屏时自动隐藏')
$miFull.Add_Click({
    $script:Cfg.hideOnFullscreen = -not $script:Cfg.hideOnFullscreen
    Export-Config
    Update-OrbMenuText
})

[void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())

$miClosePanel = $menu.Items.Add('关闭面板进程（释放内存）')
$miClosePanel.Add_Click({ Close-PanelApp })

$miReset = $menu.Items.Add('球回到默认位置')
$miReset.Add_Click({
    $script:Cfg.orbX = -1
    $script:Cfg.orbY = -1
    Export-Config
    Paint-Orb
})

$miAuto = $menu.Items.Add('开机自启')
$miAuto.Add_Click({
    if (Test-Autostart) {
        Remove-Autostart
        Write-Log '自启已关闭'
    } elseif (-not (Enable-Autostart)) {
        [void][System.Windows.Forms.MessageBox]::Show(
            "开机自启设置失败，原因写在程序目录的 orb.log 里。`r`n`r`n也可以直接双击程序目录下的「开机自启-开启.cmd」。",
            'DeepSeek 悬浮球', 'OK', 'Warning')
    }
    Update-OrbMenuText
})

$miQuit = $menu.Items.Add('退出')
$miQuit.Add_Click({
    try { Close-PanelApp } catch {}
    $form.Close()
})

$form.ContextMenuStrip = $menu

function Update-OrbMenuText {
    try {
        $miToggle.Text = if ($script:PanelOpen) { "收起面板  ($($script:Cfg.hotkey))" } else { "打开面板  ($($script:Cfg.hotkey))" }
        $miToggle.Text = $miToggle.Text -replace '（）', '()'
        $miFrameless.Checked = [bool]$script:Cfg.frameless
        $miGame.Checked      = [bool]$script:Cfg.gameMode
        $miFull.Checked      = [bool]$script:Cfg.hideOnFullscreen
        $miAuto.Checked = Test-Autostart
        $orbTxt = "球大小  $($script:Cfg.orbDip)（改 config.json 的 orbDip）"
        if (-not $script:OrbTipItem) {
            $script:OrbTipItem = [System.Windows.Forms.ToolStripMenuItem]::new($orbTxt)
            $script:OrbTipItem.Enabled = $false
            [void]$menu.Items.Insert(0, $script:OrbTipItem)
        } else {
            $script:OrbTipItem.Text = $orbTxt
        }
    } catch { Write-Log "菜单刷新失败: $($_.Exception.Message)" }
}

$menu.Add_Opening({ Update-OrbMenuText })

# =====================================================================
#  全屏检测
# =====================================================================
$fsTimer = [System.Windows.Forms.Timer]::new()
$fsTimer.Interval = 1200
$fsTimer.Add_Tick({
    try {
        if (-not $script:Cfg.hideOnFullscreen) {
            if ($script:HiddenByFullscreen) {
                $script:HiddenByFullscreen = $false
                $form.Show()
                Paint-Orb
            }
            return
        }
        $fs = [OrbNative]::IsFullscreenApp()
        if ($fs -and (-not $script:HiddenByFullscreen)) {
            $script:HiddenByFullscreen = $true
            $form.Hide()
        } elseif ((-not $fs) -and $script:HiddenByFullscreen) {
            $script:HiddenByFullscreen = $false
            $form.Show()
            Paint-Orb
        }
    } catch { Write-Log "全屏检测异常: $($_.Exception.Message)" }
})

# =====================================================================
#  启动
# =====================================================================
try {
    Update-OrbSize
    $form.Show()
    $form.Handle | Out-Null
    [OrbNative]::MakeLayeredToolWindow($form.Handle)
    $form.TopMost = $true
    Paint-Orb

    # 全局热键
    $filter = [HotkeyFilter]::new()
    $filter.add_Pressed({ Toggle-Panel })
    [System.Windows.Forms.Application]::AddMessageFilter($filter)
    $ok = [OrbNative]::RegisterHotKey($form.Handle, $script:HotkeyId, $script:HotkeyMods, $script:HotkeyVk)
    if (-not $ok) { Write-Log "热键 $($script:Cfg.hotkey) 注册失败（可能被占用）" }

    $fsTimer.Start()
    $script:EdgeExe = Find-EdgeExe
    Write-Log "启动完成 scale=$($script:Scale) orbPx=$($script:OrbPx) hotkey=$($script:Cfg.hotkey) ok=$ok edge=$($script:EdgeExe)"

    Repair-Autostart

    if ($SelfTest) {
        # 冒烟：菜单 / 配置 / 游戏模式 路径
        $script:Cfg.gameMode = $true;  Update-OrbSize; Paint-Orb; Update-OrbMenuText
        $script:Cfg.gameMode = $false; Update-OrbSize; Paint-Orb; Update-OrbMenuText
        Export-Config
        for ($i = 0; $i -lt 24; $i++) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 60
        }
        $r = $script:OrbRect
        $pad = 40
        $bw = $r[2] + $pad * 2
        $bh = $r[3] + $pad * 2
        $bmp = [System.Drawing.Bitmap]::new($bw, $bh)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try { $g.CopyFromScreen($r[0] - $pad, $r[1] - $pad, 0, 0, [System.Drawing.Size]::new($bw, $bh)) }
        catch { Write-Log "截图失败: $($_.Exception.Message)" }
        $g.Dispose()
        $out = Join-Path $script:Root 'selftest-orb.png'
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Write-Log "自检截图: $out"
        [void][OrbNative]::UnregisterHotKey($form.Handle, $script:HotkeyId)
        $form.Close()
        return
    }

    if ($PanelTest) {
        Show-Panel
        for ($i = 0; $i -lt 70; $i++) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
        $r = Get-PanelRect
        Start-Sleep -Milliseconds 300
        Save-Shot $r[0] $r[1] $r[2] $r[3] (Join-Path $script:Root 'selftest-panel.png')
        Write-Log "面板自检: $($r -join ',')"
        Close-PanelApp
        [void][OrbNative]::UnregisterHotKey($form.Handle, $script:HotkeyId)
        $form.Close()
        return
    }

    [System.Windows.Forms.Application]::Run($form)
}
catch {
    Write-Log "致命错误: $($_.Exception.Message)`r`n$($_.ScriptStackTrace)"
    throw
}
finally {
    try { [void][OrbNative]::UnregisterHotKey($form.Handle, $script:HotkeyId) } catch {}
    Write-Log '退出'
}
