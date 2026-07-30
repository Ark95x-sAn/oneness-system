param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectPath,
    [string]$Configuration = "Release"
)
if (-not (Test-Path $ProjectPath)) {
    Write-Error "Project not found: $ProjectPath"
    exit 1
}
if ($ProjectPath.EndsWith(".sln") -or $ProjectPath.EndsWith(".csproj")) {
    dotnet build $ProjectPath -c $Configuration
} else {
    Write-Error "Unsupported project type"
    exit 1
}
