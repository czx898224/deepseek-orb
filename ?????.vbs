' DeepSeek Orb launcher - keeps the PowerShell host invisible.
Option Explicit
Dim sh, fso, base, ps1
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = base & "\orb.ps1"
If Not fso.FileExists(ps1) Then
    MsgBox "orb.ps1 not found: " & ps1, 16, "DeepSeek Orb"
    WScript.Quit 1
End If
sh.Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """", 0, False
