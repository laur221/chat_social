param(
    [string]$EnvFile = "server/.env.local",
    [string]$ServerDir = "server"
)

if (-not (Test-Path $EnvFile)) {
    Write-Host "Lipsește $EnvFile. Copiază server/.env.local.example -> server/.env.local și completează GOOGLE_CLIENT_ID."
    exit 1
}

Get-Content $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { return }
    $parts = $line.Split("=", 2)
    if ($parts.Count -eq 2) {
        [System.Environment]::SetEnvironmentVariable($parts[0], $parts[1], "Process")
    }
}

Push-Location $ServerDir
try {
    python server.py
} finally {
    Pop-Location
}
