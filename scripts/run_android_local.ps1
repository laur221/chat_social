param(
    [string]$Device = "emulator-5554",
    [string]$WsHost = "ws://10.0.2.2:10000/ws",
    [string]$GoogleWebClientId = ""
)

if ([string]::IsNullOrWhiteSpace($GoogleWebClientId)) {
    $GoogleWebClientId = [System.Environment]::GetEnvironmentVariable("GOOGLE_CLIENT_ID", "User")
}
if ([string]::IsNullOrWhiteSpace($GoogleWebClientId)) {
    $GoogleWebClientId = [System.Environment]::GetEnvironmentVariable("GOOGLE_CLIENT_ID", "Process")
}
if ([string]::IsNullOrWhiteSpace($GoogleWebClientId)) {
    Write-Host "Lipsește GOOGLE_CLIENT_ID. Setează-l în server/.env.local sau la nivel de user."
    exit 1
}

flutter run -d $Device --dart-define=CHAT_WS_HOST=$WsHost --dart-define=GOOGLE_WEB_CLIENT_ID=$GoogleWebClientId
