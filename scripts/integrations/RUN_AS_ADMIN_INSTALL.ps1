#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
$log = "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\memory\logs\admin_install.log"
function Log($msg) { "$msg" | Tee-Object -FilePath $log -Append }
Log "=== Oneness Admin Installer started at $(Get-Date) ==="
Log "Running as: $(whoami)"

# Publish Oneness.Web Release if not already present
$exe = "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\publish\Oneness.Web.exe"
if (-not (Test-Path $exe)) {
    Log "Publishing Oneness.Web Release..."
    Set-Location "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\src\Oneness.Web"
    dotnet publish -c Release -o "..\..\publish" --self-contained false | Tee-Object -FilePath $log -Append
}
if (-not (Test-Path $exe)) {
    Log "ERROR: Could not publish Oneness.Web"
    exit 1
}
Log "Binary: $exe"

# Stop any existing listener on 5050
Get-NetTCPConnection -LocalPort 5050 -ErrorAction SilentlyContinue | ForEach-Object {
    Log "Stopping PID $($_.OwningProcess)"
    Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# Create / start service
Log "Installing OnenessWeb Windows service..."
$existing = Get-Service -Name OnenessWeb -ErrorAction SilentlyContinue
if ($existing) {
    sc.exe stop OnenessWeb | Tee-Object -FilePath $log -Append
    sc.exe delete OnenessWeb | Tee-Object -FilePath $log -Append
    Start-Sleep -Seconds 2
}
sc.exe create OnenessWeb binPath= "$exe" start= auto obj= "NT AUTHORITY\LOCALSERVICE" displayName= "Oneness System Web Control Center" | Tee-Object -FilePath $log -Append
sc.exe description OnenessWeb "Unified AI agent control center for trading, legal, memory, and PC operations." | Tee-Object -FilePath $log -Append
sc.exe start OnenessWeb | Tee-Object -FilePath $log -Append
Get-Service OnenessWeb | Select-Object Name, Status, StartType | Tee-Object -FilePath $log -Append

# Create scheduled tasks with highest privileges
Log "Creating scheduled tasks..."
$healthAction = New-ScheduledTaskAction -Execute "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\venv\Scripts\python.exe" -Argument "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\scripts\health_check.py"
$healthTrigger = New-ScheduledTaskTrigger -Daily -At "06:00"
$scanAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\scripts\integrations\scan_vs_projects.ps1`""
$scanTrigger = New-ScheduledTaskTrigger -Daily -At "07:00"
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName "Oneness-HealthCheck" -Action $healthAction -Trigger $healthTrigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-String | Tee-Object -FilePath $log -Append
Register-ScheduledTask -TaskName "Oneness-VSScan" -Action $scanAction -Trigger $scanTrigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-String | Tee-Object -FilePath $log -Append

# Startup shortcut
$startupDir = "C:\Users\ArcXN\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
if (-not (Test-Path $startupDir)) { New-Item -ItemType Directory -Path $startupDir -Force | Out-Null }
$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut("$startupDir\Oneness Prime Fire Council.lnk")
$sc.TargetPath = "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\scripts\run_prime_fire_council.bat"
$sc.WorkingDirectory = "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem"
$sc.Save()
Log "Startup shortcut created."

Log "=== Admin Installer completed at $(Get-Date) ==="
