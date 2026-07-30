# Q2 — Start Qdrant + Index Documents
# Tries Docker, then local qdrant.exe, then falls back to Python TF-IDF indexer.
param(
    [switch]$UseFallback
)

$ErrorActionPreference = "Stop"
$root = "$env:USERPROFILE\OneDrive\Desktop\OnenessSystem"

function Start-DockerQdrant {
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $docker) { return $false }
    try {
        $info = docker info 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
    } catch { return $false }
    docker run -d -p 6333:6333 -v "$root\memory\qdrant_storage:/qdrant/storage" qdrant/qdrant:latest 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Qdrant started via Docker on port 6333" -ForegroundColor Green
        return $true
    }
    return $false
}

function Start-LocalQdrant {
    $qdrant = "$env:USERPROFILE\bin\qdrant.exe"
    if (Test-Path $qdrant) {
        Start-Process -FilePath $qdrant -ArgumentList "--config-path", "$root\config\qdrant.yaml" -WindowStyle Hidden
        Write-Host "Qdrant started from $qdrant" -ForegroundColor Green
        return $true
    }
    return $false
}

function Start-FallbackIndexer {
    cd $root
    $env:PYTHONPATH = "$root\src"
    .\venv\Scripts\python.exe .\src\memory\indexer.py
    Write-Host "Fallback TF-IDF indexer active" -ForegroundColor Yellow
}

if ($UseFallback) {
    Start-FallbackIndexer
} elseif (-not (Start-DockerQdrant)) {
    if (-not (Start-LocalQdrant)) {
        Write-Host "No native Qdrant available. Running fallback indexer." -ForegroundColor Yellow
        Start-FallbackIndexer
    }
}

Write-Host "Q2 complete. Index lives at memory/qdrant_fallback/index.json or localhost:6333" -ForegroundColor Green
