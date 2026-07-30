$exe = "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\src\Oneness.Web\bin\Release\net10.0\Oneness.Web.exe"
if (-not (Test-Path $exe)) {
    Write-Host "Building release binary..."
    Set-Location "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\src\Oneness.Web"
    dotnet publish -c Release -o ..\..\publish --self-contained false
    $exe = "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\publish\Oneness.Web.exe"
}
if (-not (Test-Path $exe)) {
    Write-Error "Could not build/publish Oneness.Web"
    exit 1
}
sc.exe create OnenessWeb binPath= "$exe" start= auto obj= "NT AUTHORITY\LOCALSERVICE" displayName= "Oneness System Web Control Center"
sc.exe description OnenessWeb "Unified AI agent control center for trading, legal, memory, and PC operations."
sc.exe start OnenessWeb
Write-Host "OnenessWeb service installed/started (admin required)"
