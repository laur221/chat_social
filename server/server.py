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
    # Load credentials from a file. Trim whitespace and avoid logging secrets.
    if os.path.exists(file_path):
        with open(file_path, "r") as file:
            for line in file:
                parts = line.strip().split(":")
                if len(parts) == 2:
                    username = parts[0].strip()
                    password = parts[1].strip()
                    if username:
                        credentials[username] = password
    else:
        # Fallback: try repository-local password file for development convenience
        alt_path = os.path.join(os.path.dirname(__file__), "password.txt")
        if os.path.exists(alt_path):
            with open(alt_path, "r") as file:
                for line in file:
                    parts = line.strip().split(":")
                    if len(parts) == 2:
                        username = parts[0].strip()
                        password = parts[1].strip()
                        if username:
                            credentials[username] = password
        else:
            # Default test users (only used if no file is present)
            credentials["1"] = "1"
            credentials["2"] = "2"

    # Do not print passwords. Only print counts for debug.
    print(f"[DEBUG] Total credentials loaded: {len(credentials)}", flush=True)
    return credentials

user_credentials = load_credentials("/etc/secrets/password.txt")

# ===============================
# Broadcast mesaje
# ===============================
async def broadcast_message(message: dict, exclude_ws: web.WebSocketResponse = None):
    if not connected_clients:
        return
    msg = json.dumps(message)
    
    # Broadcast la toți clienții, cu excepție opțională
    targets = [ws for ws in connected_clients if ws != exclude_ws]
    await asyncio.gather(
        *[ws.send_str(msg) for ws in targets], return_exceptions=True
    )

async def broadcast_user_list():
    """Broadcast lista de utilizatori la toți clienții autentificați"""
    for client_username, client_ws in user_connections.items():
        other_users = [u for u in user_connections.keys() if u != client_username]
        try:
            await client_ws.send_str(
                json.dumps({"type": "user_list", "users": other_users})
            )
            print(f"[DEBUG] Sent user_list to {client_username}: {other_users}", flush=True)
        except Exception as e:
            print(f"[DEBUG] Error sending user_list to {client_username}: {e}", flush=True)

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
                        username = (data.get("username") or "").strip()
                        password = (data.get("password") or "").strip()
                        print(f"[DEBUG] Auth attempt - User: '{username}'", flush=True)

                        user_exists = username in user_credentials
                        print(f"[DEBUG] User exists in credentials: {user_exists}", flush=True)

                        if user_exists and user_credentials.get(username, "") == password:
                            user_connections[username] = ws
                            print(f"[DEBUG] Auth SUCCESS for {username}", flush=True)

                            # Trimite auth_success
                            await ws.send_str(json.dumps({"type": "auth_success", "message": "Autentificare reușită"}))

                            # Trimite lista de utilizatori
                            await broadcast_user_list()
                        else:
                            print(f"[DEBUG] Auth FAILED for {username}", flush=True)
                            await ws.send_str(json.dumps({"type": "auth_error", "message": "Username sau parolă greșită"}))

                    elif msg_type == "message" and username:
                        msg_text = data.get("message", "")
                        print(f"[DEBUG] Public message from {username}: {msg_text}", flush=True)
                        await broadcast_message({
                            "type": "message",
                            "username": username,
                            "message": msg_text,
                            "timestamp": datetime.now().isoformat(),
                        })

                    elif msg_type == "private_message" and username:
                        target = data.get("target")
                        msg_text = data.get("message", "")
                        print(f"[DEBUG] Private message from {username} to {target}", flush=True)
                        
                        # Trimite la destinatar
                        if target in user_connections:
                            target_ws = user_connections[target]
                            await target_ws.send_str(json.dumps({
                                "type": "private_message",
                                "username": username,
                                "target": target,
                                "message": msg_text,
                                "timestamp": datetime.now().isoformat(),
                            }))
                            print(f"[DEBUG] Private message sent to {target}", flush=True)
                        else:
                            print(f"[DEBUG] Target {target} not connected", flush=True)
                            # Informă expeditorul că destinatarul nu e online
                            await ws.send_str(json.dumps({
                                "type": "error",
                                "message": f"Utilizatorul {target} nu este conectat"
                            }))

                    elif msg_type == "create_group" and username:
                        group_name = data.get("group_name")
                        if group_name and group_name not in groups:
                            groups[group_name] = set()
                            groups[group_name].add(username)
                            print(f"[DEBUG] Group created: {group_name} by {username}", flush=True)
                            
                            # Trimite confirmare expeditorului
                            await ws.send_str(json.dumps({
                                "type": "group_created",
                                "group_name": group_name,
                                "creator": username
                            }))
                            
                            # Broadcast la toți
                            await broadcast_message({
                                "type": "group_created",
                                "group_name": group_name,
                                "creator": username
                            })
                        else:
                            print(f"[DEBUG] Group {group_name} already exists", flush=True)

                    elif msg_type == "add_to_group" and username:
                        group_name = data.get("group_name")
                        member = data.get("member")
                        print(f"[DEBUG] Add {member} to group {group_name} by {username}", flush=True)
                        
                        if group_name in groups and member in user_connections:
                            groups[group_name].add(member)
                            print(f"[DEBUG] Added {member} to {group_name}", flush=True)
                            
                            # Trimite confirmare expeditorului
                            await ws.send_str(json.dumps({
                                "type": "added_to_group",
                                "group_name": group_name
                            }))
                            
                            # Trimite notificare membrului adăugat
                            member_ws = user_connections[member]
                            await member_ws.send_str(json.dumps({
                                "type": "added_to_group",
                                "group_name": group_name
                            }))

                    elif msg_type == "group_message" and username:
                        group_name = data.get("group")
                        msg_text = data.get("message", "")
                        print(f"[DEBUG] Group message from {username} in {group_name}", flush=True)
                        
                        # Trimite la toți membrii grupului
                        if group_name in groups:
                            for member in groups[group_name]:
                                if member in user_connections:
                                    member_ws = user_connections[member]
                                    await member_ws.send_str(json.dumps({
                                        "type": "group_message",
                                        "username": username,
                                        "group": group_name,
                                        "message": msg_text,
                                        "timestamp": datetime.now().isoformat(),
                                    }))
                            print(f"[DEBUG] Group message sent to {len(groups[group_name])} members", flush=True)

                    elif msg_type == "typing" and username:
                        target = data.get("target")
                        is_typing = data.get("typing", False)
                        print(f"[DEBUG] Typing indicator from {username} to {target}: {is_typing}", flush=True)
                        
                        if target in user_connections:
                            target_ws = user_connections[target]
                            await target_ws.send_str(json.dumps({
                                "type": "typing",
                                "username": username,
                                "target": target,
                                "typing": is_typing
                            }))

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
