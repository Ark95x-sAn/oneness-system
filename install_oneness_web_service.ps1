# install_oneness_web_service.ps1
[CmdletBinding()]
param(
    [string]$Root = 'C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem',
    [string]$ServiceName = 'OnenessWeb',
    [string]$Url = 'http://localhost:5050/api/subagents/status'
)
$ErrorActionPreference = 'Stop'
$PublishDir = Join-Path $Root 'publish'
$Project = Join-Path $Root 'src' 'Oneness.Web' 'Oneness.Web.csproj'
$Exe = Join-Path $PublishDir 'Oneness.Web.exe'
function Wait-Api {
    param([int]$MaxSeconds = 60)
    for ($i = 0; $i -lt $MaxSeconds; $i++) {
        try {
            $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
            if ($r.StatusCode -eq 200) { return $true }
        } catch { }
        Start-Sleep -Seconds 1
    }
    return $false
}
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host 'Stopping existing service...'
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    $wmi = Get-WmiObject Win32_Service -Filter "Name='$ServiceName'"
    if ($wmi) { $wmi.Delete() | Out-Null }
    Start-Sleep -Seconds 2
}
Write-Host 'Publishing Oneness.Web...'
if (Test-Path $PublishDir) { Remove-Item -Path $PublishDir -Recurse -Force }
dotnet publish $Project -c Release -o $PublishDir --self-contained false -p:PublishSingleFile=false
if (-not (Test-Path $Exe)) { throw "Publish failed: $Exe not found" }
Write-Host 'Creating service...'
New-Service -Name $ServiceName -BinaryPathName "$Exe --urls http://localhost:5050" -DisplayName 'Oneness System Web Control Center' -StartupType Automatic -Description 'Hosts the Oneness Web dashboard and API.' | Out-Null
sc config $ServiceName start= auto | Out-Null
sc config $ServiceName type= own | Out-Null
Start-Service -Name $ServiceName
if (Wait-Api -MaxSeconds 60) {
    Write-Host 'OnenessWeb service is running and API is responding.' -ForegroundColor Green
} else {
    throw 'Service started but API did not respond within 60 seconds.'
}
