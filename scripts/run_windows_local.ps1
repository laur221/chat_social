param(
    [string]$WsHost = "ws://127.0.0.1:10000/ws"
)

flutter run -d windows --dart-define=CHAT_WS_HOST=$WsHost
