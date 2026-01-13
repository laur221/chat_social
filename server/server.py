import asyncio
import websockets
import json
from datetime import datetime
from websockets.legacy.server import WebSocketServerProtocol
import os
import logging
from typing import Set, Dict

# Suprimare erori handshake pentru health checks
logging.getLogger("websockets.server").setLevel(logging.CRITICAL)
logging.getLogger("websockets.protocol").setLevel(logging.CRITICAL)

# ===============================
# Conexiuni și grupuri
# ===============================
connected_clients: Set[WebSocketServerProtocol] = set()
user_connections: Dict[str, WebSocketServerProtocol] = {}
groups: Dict[str, Set[str]] = {"General": set()}

# ===============================
# Încarcă utilizatorii și parolele din fișier
# ===============================
def load_credentials(file_path="password.txt"):
    credentials = {}
    if os.path.exists(file_path):
        with open(file_path, "r") as file:
            for line in file:
                parts = line.strip().split(":")
                if len(parts) == 2:
                    username, password = parts
                    credentials[username] = password
    return credentials

user_credentials = load_credentials()

# ===============================
# Health check pentru Render
# ===============================
async def process_request(path, request_headers):
    upgrade = request_headers.get("Upgrade", "").lower()
    if upgrade == "websocket":
        return None  # permite upgrade WebSocket
    # răspuns simplu pentru health checks
    return (200, [("Content-Type", "text/plain")], b"OK")

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
    for username, ws in user_connections.items():
        other_users = [u for u in user_connections.keys() if u != username]
        try:
            await ws.send(json.dumps({"type": "user_list", "users": other_users}))
        except:
            pass

# ===============================
# Handler client
# ===============================
async def handle_client(ws: WebSocketServerProtocol):
    print(f"[DEBUG] Client conectat: {ws.remote_address}", flush=True)
    connected_clients.add(ws)
    username = None

    try:
        async for msg in ws:
            try:
                data = json.loads(msg)
            except json.JSONDecodeError:
                continue

            msg_type = data.get("type")

            if msg_type == "auth":
                username = data.get("username")
                password = data.get("password")
                if username in user_credentials and user_credentials[username] == password:
                    user_connections[username] = ws
                    await ws.send(json.dumps({"type": "auth_success", "message": "Autentificare reușită"}))
                    print(f"[DEBUG] Autentificat: {username}", flush=True)
                else:
                    await ws.send(json.dumps({"type": "auth_error", "message": "Username/parolă greșită"}))

            elif msg_type == "message" and username:
                text = data.get("message", "")
                await broadcast_message({
                    "type": "message",
                    "username": username,
                    "message": text,
                    "timestamp": datetime.now().isoformat()
                })
                print(f"{username}: {text}", flush=True)

            elif msg_type == "private_message" and username:
                target = data.get("target")
                text = data.get("message", "")
                if target in user_connections:
                    await user_connections[target].send(json.dumps({
                        "type": "private_message",
                        "username": username,
                        "target": target,
                        "message": text,
                        "timestamp": datetime.now().isoformat()
                    }))

    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        connected_clients.discard(ws)
        if username and username in user_connections:
            del user_connections[username]
        await broadcast_user_list()
        print(f"[DEBUG] Client deconectat: {username}", flush=True)

# ===============================
# Main
# ===============================
async def main():
    host = "0.0.0.0"
    port = int(os.environ.get("PORT", 8080))  # folosește portul din Render

    print("="*50, flush=True)
    print("Server WebSocket pentru Chat Social", flush=True)
    print(f"Ascultă pe ws://{host}:{port}", flush=True)
    print("="*50, flush=True)

    async with websockets.serve(handle_client, host, port, process_request=process_request):
        await asyncio.Future()  # infinit

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nServer oprit.", flush=True)
