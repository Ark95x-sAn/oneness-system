# run_web_app.ps1 — starts the current Oneness.Web build without admin / without Windows service
param(
    [int]$Port = 5051,
    [string]$Urls = "http://localhost:$Port"
)
$Root = "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem"
$Exe = "$Root\src\Oneness.Web\bin\Release\net10.0\Oneness.Web.exe"
if (-not (Test-Path $Exe)) {
    Write-Host "Building current Oneness.Web..."
    dotnet publish "$Root\src\Oneness.Web\Oneness.Web.csproj" -c Release -o "$Root\src\Oneness.Web\bin\Release\net10.0" --no-restore
}
$proc = Start-Process -FilePath $Exe -ArgumentList "--urls", $Urls -WorkingDirectory "$Root\src\Oneness.Web" -WindowStyle Hidden -PassThru
Write-Host "Started Oneness.Web PID $($proc.Id) on $Urls"
