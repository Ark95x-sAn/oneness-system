param(
    [string[]]$Roots = @(
        "C:\Users\ArcXN\OneDrive\Desktop",
        "C:\Users\ArcXN\OneDrive\Documents",
        "C:\Users\ArcXN\source",
        "C:\Users\ArcXN\Downloads"
    ),
    [string]$Output = "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\memory\logs\vs_projects.json"
)
$results = @()
foreach ($r in $Roots) {
    if (-not (Test-Path $r)) { continue }
    $slns = Get-ChildItem -Path $r -Recurse -Filter *.sln -ErrorAction SilentlyContinue
    $csprojs = Get-ChildItem -Path $r -Recurse -Filter *.csproj -ErrorAction SilentlyContinue
    $jsprojs = Get-ChildItem -Path $r -Recurse -Filter package.json -ErrorAction SilentlyContinue
    $results += [PSCustomObject]@{
        Root = $r
        Solutions = @($slns | Select-Object FullName, LastWriteTime)
        CSharpProjects = @($csprojs | Select-Object FullName, LastWriteTime)
        NodeProjects = @($jsprojs | Select-Object FullName, LastWriteTime)
    }
}
$results | ConvertTo-Json -Depth 5 | Set-Content -Path $Output -Encoding utf8NoBOM
Write-Host "Scanned projects written to $Output"

