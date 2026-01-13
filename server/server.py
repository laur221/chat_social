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
    print(f"[DEBUG] Loading credentials from: {file_path}", flush=True)
    
    if os.path.exists(file_path):
        print(f"[DEBUG] File {file_path} exists", flush=True)
        with open(file_path, "r") as file:
            for line in file:
                parts = line.strip().split(":")
                if len(parts) == 2:
                    username, password = parts
                    credentials[username] = password
                    print(f"[DEBUG] Loaded user: {username}", flush=True)
    else:
        print(f"[DEBUG] File {file_path} NOT FOUND!", flush=True)
    
    print(f"[DEBUG] Total credentials loaded: {len(credentials)}", flush=True)
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
# WebSocket handler pe path /ws
# ===============================
async def websocket_handler(request: web.Request):
    print(f"[DEBUG] WebSocket request received from {request.remote}", flush=True)
    
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    
    print(f"[DEBUG] WebSocket connection established with {request.remote}", flush=True)
    
    connected_clients.add(ws)
    username = None

    try:
        # Trimite welcome message imediat
        await ws.send_str(json.dumps({"type": "welcome", "message": "Conectat la server"}))
        print(f"[DEBUG] Welcome message sent to {request.remote}", flush=True)
        
        async for msg in ws:
            if msg.type == web.WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                    msg_type = data.get("type")

                    if msg_type == "auth":
                        username = data.get("username")
                        password = data.get("password")
                        print(f"[DEBUG] Auth attempt - User: '{username}', Password: '{password}'", flush=True)
                        print(f"[DEBUG] User exists in credentials: {username in user_credentials}", flush=True)
                        
                        if username in user_credentials:
                            print(f"[DEBUG] Stored password for {username}: '{user_credentials[username]}'", flush=True)
                        
                        if username in user_credentials and user_credentials[username] == password:
                            user_connections[username] = ws
                            print(f"[DEBUG] Auth SUCCESS for {username}", flush=True)
                            await ws.send_str(json.dumps({"type": "auth_success", "message": "Autentificare reușită"}))
                        else:
                            print(f"[DEBUG] Auth FAILED for {username}", flush=True)
                            await ws.send_str(json.dumps({"type": "auth_error", "message": "Username sau parolă greșită"}))

                    elif msg_type == "message" and username:
                        msg_text = data.get("message", "")
                        print(f"[DEBUG] Message from {username}: {msg_text}", flush=True)
                        await broadcast_message({
                            "type": "message",
                            "username": username,
                            "message": msg_text,
                            "timestamp": datetime.now().isoformat(),
                        })

                except json.JSONDecodeError as e:
                    print(f"[DEBUG] JSON decode error: {e}", flush=True)
            
            elif msg.type == web.WSMsgType.ERROR:
                print(f"[DEBUG] WebSocket error: {ws.exception()}", flush=True)
            
            elif msg.type == web.WSMsgType.CLOSE:
                print(f"[DEBUG] WebSocket close message received", flush=True)
                break

    except Exception as e:
        print(f"[DEBUG] Exception in WebSocket handler: {e}", flush=True)
    finally:
        print(f"[DEBUG] WebSocket disconnecting {username or 'unknown user'}", flush=True)
        connected_clients.discard(ws)
        if username and username in user_connections:
            del user_connections[username]
            for group_name in groups:
                groups[group_name].discard(username)
            await broadcast_user_list()
    
    return ws

# ===============================
# Health check handler pe root /
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
    print(f"WebSocket la ws://{host}:{port}/ws")
    print(f"Health check la http://{host}:{port}/")
    print("="*50)
    
    # Creare aplicație
    app = web.Application()
    
    # Route pentru health check la root
    app.router.add_get("/", health_check)
    
    # Route pentru WebSocket la /ws
    app.router.add_get("/ws", websocket_handler)
    
    # Pornire server
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, host, port)
    
    print(f"[DEBUG] Server pornit și ascultă pe {host}:{port}", flush=True)
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
