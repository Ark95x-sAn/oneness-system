$action = New-ScheduledTaskAction -Execute "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\venv\Scripts\python.exe" -Argument "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\scripts\health_check.py"
$trigger = New-ScheduledTaskTrigger -Daily -At "06:00"
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive
Register-ScheduledTask -TaskName "Oneness-HealthCheck" -Action $action -Trigger $trigger -Principal $principal -Force

$scanAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\scripts\integrations\scan_vs_projects.ps1"
$scanTrigger = New-ScheduledTaskTrigger -Daily -At "07:00"
Register-ScheduledTask -TaskName "Oneness-VSScan" -Action $scanAction -Trigger $scanTrigger -Principal $principal -Force
Write-Host "Scheduled tasks created"
