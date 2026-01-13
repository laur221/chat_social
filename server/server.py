import asyncio
import websockets
import json
from datetime import datetime
from typing import Set, Dict
from websockets.legacy.server import WebSocketServerProtocol
import os
import logging
from aiohttp import web

# ===============================
# Configure logging
# ===============================
logging.getLogger("websockets.server").setLevel(logging.CRITICAL)
logging.getLogger("websockets.protocol").setLevel(logging.CRITICAL)

# ===============================
# Process request (pentru health check WebSocket)
# ===============================
async def process_request(path, request_headers):
    upgrade = request_headers.get("Upgrade", "").lower()
    if upgrade == "websocket":
        return None  # permite upgrade la WebSocket
    # Health check HTTP pe WebSocket
    return (200, [("Content-Type", "text/plain")], b"OK")

# ===============================
# Conexiuni
# ===============================
connected_clients: Set[WebSocketServerProtocol] = set()
user_connections: Dict[str, WebSocketServerProtocol] = {}
groups: Dict[str, Set[str]] = {"General": set()}

# ===============================
# Încarcă utilizatorii și parolele
# ===============================
def load_credentials(file_path):
    credentials = {}
    if os.path.exists(file_path):
        with open(file_path, "r") as file:
            for line in file:
                parts = line.strip().split(":")
                if len(parts) == 2:
                    username, password = parts
                    credentials[username] = password
    return credentials

user_credentials = load_credentials("password.txt")

# ===============================
# Broadcast mesaje
# ===============================
async def broadcast_message(message: dict):
    if not connected_clients:
        return
    msg = json.dumps(message)
    await asyncio.gather(
        *[client.send(msg) for client in connected_clients], return_exceptions=True
    )

async def broadcast_user_list():
    for client_username, client_ws in user_connections.items():
        other_users = [u for u in user_connections.keys() if u != client_username]
        try:
            await client_ws.send(
                json.dumps({"type": "user_list", "users": other_users})
            )
        except Exception as e:
            print(f"Eroare la trimitere lista către {client_username}: {e}", flush=True)

# ===============================
# WebSocket handler
# ===============================
async def handle_client(websocket: WebSocketServerProtocol):
    print(f"[DEBUG] Client conectat: {websocket.remote_address}", flush=True)
    connected_clients.add(websocket)
    username = None

    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                msg_type = data.get("type")

                if msg_type == "auth":
                    username = data.get("username")
                    password = data.get("password")
                    if username in user_credentials and user_credentials[username] == password:
                        user_connections[username] = websocket
                        await websocket.send(json.dumps({"type": "auth_success","message": "Autentificare reușită"}))
                    else:
                        await websocket.send(json.dumps({"type": "auth_error","message": "Username sau parolă greșită"}))

                elif msg_type == "message" and username:
                    msg_text = data.get("message", "")
                    await broadcast_message({
                        "type": "message",
                        "username": username,
                        "message": msg_text,
                        "timestamp": datetime.now().isoformat(),
                    })

                # Mai multe tipuri de mesaje (grup, PM, typing etc.) se pot păstra ca în codul tău

            except json.JSONDecodeError:
                print(f"[DEBUG] Mesaj JSON invalid: {message}", flush=True)

    except websockets.exceptions.ConnectionClosed:
        print(f"[DEBUG] Conexiune închisă: {websocket.remote_address}", flush=True)
    finally:
        connected_clients.discard(websocket)
        if username and username in user_connections:
            del user_connections[username]
            for group_name in groups:
                groups[group_name].discard(username)
            await broadcast_user_list()

# ===============================
# HTTP health check endpoint
# ===============================
async def health(request):
    return web.Response(text="OK")

# ===============================
# Main server
# ===============================
async def main():
    ws_port = int(os.environ.get("PORT", 8080))  # Render folosește PORT pentru WebSocket
    http_port = ws_port + 1  # HTTP pe portul următor
    host = "0.0.0.0"

    print("="*50)
    print(f"Server WebSocket + HTTP pentru Chat Social")
    print(f"WebSocket pe ws://{host}:{ws_port}")
    print(f"Health check HTTP la http://{host}:{http_port}/")
    print("="*50)

    # Pornim server WebSocket pe ws_port
    ws_server = websockets.serve(handle_client, host, ws_port, process_request=process_request)

    # Pornim server HTTP cu aiohttp pe http_port
    http_app = web.Application()
    http_app.router.add_get("/", health)
    runner = web.AppRunner(http_app)
    await runner.setup()
    site = web.TCPSite(runner, host, http_port)

    # Rulează ambele servere concurent
    await asyncio.gather(ws_server, site.start())

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nServer oprit.")
