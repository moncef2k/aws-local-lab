# Windows notification when Claude Code stops or needs a permission.
# Uses only built-in .NET classes, no modules to install.

$message = "Your turn: review the step, then type 'next'."
try {
    $raw = [Console]::In.ReadToEnd()
    if ($raw) {
        $data = $raw | ConvertFrom-Json
        if ($data.hook_event_name -eq "Notification" -and $data.message) {
            $message = $data.message
        }
    }
} catch { }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$balloon = New-Object System.Windows.Forms.NotifyIcon
$balloon.Icon = [System.Drawing.SystemIcons]::Information
$balloon.BalloonTipTitle = "Claude Code - aws-local-lab"
$balloon.BalloonTipText = $message
$balloon.Visible = $true
$balloon.ShowBalloonTip(5000)
Start-Sleep -Seconds 6
$balloon.Dispose()
