import asyncio
import json
from datetime import datetime
from typing import Set, Dict
import os
import logging
from aiohttp import web

# ===============================
# Configure logging
# ===============================
logging.getLogger("aiohttp.server").setLevel(logging.CRITICAL)

# ===============================
# Conexiuni
# ===============================
connected_clients: Set[web.WebSocketResponse] = set()
user_connections: Dict[str, web.WebSocketResponse] = {}
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
        *[ws.send_str(msg) for ws in connected_clients], return_exceptions=True
    )

async def broadcast_user_list():
    for client_username, client_ws in user_connections.items():
        other_users = [u for u in user_connections.keys() if u != client_username]
        try:
            await client_ws.send_str(
                json.dumps({"type": "user_list", "users": other_users})
            )
        except Exception as e:
            print(f"Eroare la trimitere lista către {client_username}: {e}", flush=True)

# ===============================
# WebSocket upgrade handler
# ===============================
async def websocket_handler(request: web.Request):
    # Verifică dacă este WebSocket upgrade sau health check
    if request.headers.get("Upgrade", "").lower() != "websocket":
        # Health check - returnează OK
        print(f"[DEBUG] Health check de la {request.remote}", flush=True)
        return web.Response(text="OK", status=200)
    
    # WebSocket upgrade
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    
    print(f"[DEBUG] Client conectat: {request.remote}", flush=True)
    connected_clients.add(ws)
    username = None

    try:
        async for msg in ws:
            if msg.type == web.WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                    msg_type = data.get("type")

                    if msg_type == "auth":
                        username = data.get("username")
                        password = data.get("password")
                        if username in user_credentials and user_credentials[username] == password:
                            user_connections[username] = ws
                            await ws.send_str(json.dumps({"type": "auth_success", "message": "Autentificare reușită"}))
                        else:
                            await ws.send_str(json.dumps({"type": "auth_error", "message": "Username sau parolă greșită"}))

                    elif msg_type == "message" and username:
                        msg_text = data.get("message", "")
                        await broadcast_message({
                            "type": "message",
                            "username": username,
                            "message": msg_text,
                            "timestamp": datetime.now().isoformat(),
                        })

                except json.JSONDecodeError:
                    print(f"[DEBUG] Mesaj JSON invalid: {msg.data}", flush=True)

    except Exception as e:
        print(f"[DEBUG] Eroare WebSocket: {e}", flush=True)
    finally:
        connected_clients.discard(ws)
        if username and username in user_connections:
            del user_connections[username]
            for group_name in groups:
                groups[group_name].discard(username)
            await broadcast_user_list()
    
    return ws

# ===============================
# Health check handler
# ===============================
async def health_check(request: web.Request):
    print(f"[DEBUG] Health check de la {request.remote}", flush=True)
    return web.Response(text="OK", status=200)

# ===============================
# Main server
# ===============================
async def main():
    port = int(os.environ.get("PORT", 10000))
    host = "0.0.0.0"

    print("="*50)
    print(f"Server WebSocket pentru Chat Social")
    print(f"Ascultă pe ws://{host}:{port}")
    print(f"Health check la http://{host}:{port}/")
    print("="*50)
    
    # Creare aplicație
    app = web.Application()
    
    # Route pentru WebSocket upgrade la root
    app.router.add_get("/", websocket_handler)
    
    # Pornire server
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, host, port)
    
    print(f"[DEBUG] Server pornit și ascultă...", flush=True)
    await site.start()
    
    # Ține serverul pornit
    try:
        await asyncio.Future()
    finally:
        await runner.cleanup()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nServer oprit.", flush=True)
