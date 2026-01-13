import asyncio
import websockets
import json
from datetime import datetime
from typing import Set, Dict
from websockets.legacy.server import WebSocketServerProtocol
import os
import signal
import logging
import sys

# Configure logging to suppress websockets handshake errors from health checks
logging.getLogger("websockets.server").setLevel(logging.CRITICAL)
logging.getLogger("websockets.protocol").setLevel(logging.CRITICAL)


# Suppress tracebacks for websockets.exceptions.InvalidMessage
class TracebackFilter:
    def __init__(self):
        self.original_excepthook = sys.excepthook

    def custom_excepthook(self, exc_type, exc_value, exc_traceback):
        # Suppress websockets handshake errors
        if exc_type == websockets.exceptions.InvalidMessage:
            return
        # Suppress EOFError from websockets
        if exc_type == EOFError:
            return
        # Show all other exceptions
        self.original_excepthook(exc_type, exc_value, exc_traceback)


sys.excepthook = TracebackFilter().custom_excepthook


# Define of process_request function at top of the file
async def process_request(path, request_headers):
    print(f"[DEBUG] Cerere primită: Path={path}, Headers={request_headers}", flush=True)

    # Check if this is a WebSocket upgrade request
    upgrade = request_headers.get("Upgrade", "").lower()
    if upgrade == "websocket":
        # Return None to allow WebSocket upgrade
        print(f"[DEBUG] WebSocket upgrade request detected", flush=True)
        return None

    # For non-WebSocket requests (health checks), return OK
    print(f"[DEBUG] Health check request, returning 200 OK", flush=True)
    return (200, [("Content-Type", "text/plain")], b"OK")


# ===============================
# Stocare conexiuni
# ===============================
connected_clients: Set[WebSocketServerProtocol] = set()
user_connections: Dict[str, WebSocketServerProtocol] = {}
# Grupele cu membrii lor: {nume_grup: [nume_utilizator1, nume_utilizator2, ...]}
groups: Dict[str, Set[str]] = {"General": set()}


# ===============================
# Încarcă utilizatorii și parolele din fișier
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
# Autentificare pe server (mutată în handle_client)
# ===============================
async def handle_client(websocket: WebSocketServerProtocol):
    print(f"[DEBUG] Client conectat de la: {websocket.remote_address}", flush=True)
    connected_clients.add(websocket)
    username = None

    try:
        async for message in websocket:
            print(f"[DEBUG] Mesaj primit: {message}", flush=True)
            try:
                data = json.loads(message)
                print(f"[DEBUG] Mesaj JSON valid: {data}", flush=True)
                msg_type = data.get("type")

                # =========================
                # Autentificare
                # =========================
                if msg_type == "auth":
                    username = data.get("username")
                    password = data.get("password")

                    # Verifică utilizatorul și parola
                    if (
                        username in user_credentials
                        and user_credentials[username] == password
                    ):
                        user_connections[username] = websocket
                        await websocket.send(
                            json.dumps(
                                {
                                    "type": "auth_success",
                                    "message": "Autentificare reușită",
                                }
                            )
                        )
                        print(f"Utilizator autentificat: {username}", flush=True)
                    else:
                        await websocket.send(
                            json.dumps(
                                {
                                    "type": "auth_error",
                                    "message": "Nume de utilizator sau parolă greșită",
                                }
                            )
                        )

                # =========================
                # Typing indicator
                # =========================
                elif msg_type == "typing" and username:
                    target = data.get("target")
                    is_typing = data.get("typing", True)

                    # Trimite indicatorul de typing către destinatar
                    if target in user_connections and target != username:
                        await user_connections[target].send(
                            json.dumps(
                                {
                                    "type": "typing",
                                    "username": username,
                                    "typing": is_typing,
                                    "target": target,
                                }
                            )
                        )

                # =========================
                # Mesaj public (Chat General)
                # =========================
                elif msg_type == "message" and username:
                    msg_text = data.get("message", "")

                    await broadcast_message(
                        {
                            "type": "message",
                            "username": username,
                            "message": msg_text,
                            "timestamp": datetime.now().isoformat(),
                        }
                    )

                    print(f"{username}: {msg_text}", flush=True)

                # =========================
                # Mesaj în grup
                # =========================
                elif msg_type == "group_message" and username:
                    group_name = data.get("group")
                    msg_text = data.get("message", "")

                    if group_name in groups:
                        group_members = groups[group_name]
                        msg_json = json.dumps(
                            {
                                "type": "group_message",
                                "username": username,
                                "group": group_name,
                                "message": msg_text,
                                "timestamp": datetime.now().isoformat(),
                            }
                        )

                        # Trimite mesajul către toți membrii grupului
                        for member in group_members:
                            if member in user_connections:
                                try:
                                    await user_connections[member].send(msg_json)
                                except Exception as e:
                                    print(
                                        f"Eroare la trimitere mesaj grup către {member}: {e}",
                                        flush=True,
                                    )
                        print(
                            f"{username} în grupul {group_name}: {msg_text}", flush=True
                        )

                # =========================
                # Mesaj privat
                # =========================
                elif msg_type == "private_message" and username:
                    target = data.get("target")
                    msg_text = data.get("message", "")

                    if target in user_connections:
                        await user_connections[target].send(
                            json.dumps(
                                {
                                    "type": "private_message",
                                    "username": username,
                                    "target": target,
                                    "message": msg_text,
                                    "timestamp": datetime.now().isoformat(),
                                }
                            )
                        )

                        print(f"PM {username} -> {target}", flush=True)

                # =========================
                # Creare grup
                # =========================
                elif msg_type == "create_group" and username:
                    group_name = data.get("group_name")

                    if group_name and group_name not in groups:
                        groups[group_name] = {username}  # Creatorul este primul membru
                        await broadcast_message(
                            {
                                "type": "group_created",
                                "group_name": group_name,
                                "creator": username,
                                "timestamp": datetime.now().isoformat(),
                            }
                        )
                        print(f"Grup creat: {group_name} de {username}", flush=True)

                # =========================
                # Adaugă membru la grup
                # =========================
                elif msg_type == "add_to_group" and username:
                    group_name = data.get("group_name")
                    member_to_add = data.get("member")

                    if group_name in groups and member_to_add in user_connections:
                        if member_to_add not in groups[group_name]:
                            groups[group_name].add(member_to_add)
                            # Notifică membrul adăugat
                            await user_connections[member_to_add].send(
                                json.dumps(
                                    {
                                        "type": "added_to_group",
                                        "group_name": group_name,
                                        "added_by": username,
                                    }
                                )
                            )
                            print(
                                f"{member_to_add} adăugat în grupul {group_name} de {username}",
                                flush=True,
                            )

            except json.JSONDecodeError:
                print(f"[DEBUG] Mesaj JSON invalid: {message}", flush=True)

    except websockets.exceptions.ConnectionClosed as e:
        print(f"[DEBUG] Conexiune închisă: {e}", flush=True)
    except websockets.exceptions.InvalidMessage:
        # This happens when health check or other non-WebSocket connections occur
        print(f"[DEBUG] Conexiune non-WebSocket (probabil health check)", flush=True)
    except Exception as e:
        print(f"[DEBUG] Eroare la manipularea clientului: {e}", flush=True)
    finally:
        print(f"[DEBUG] Client deconectat: {websocket.remote_address}", flush=True)
        connected_clients.discard(websocket)
        if username and username in user_connections:
            del user_connections[username]
            # Șterge utilizatorul din toate grupurile
            for group_name in groups:
                if username in groups[group_name]:
                    groups[group_name].discard(username)
            print(f"Utilizator șters: {username}", flush=True)
            await broadcast_user_list()


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


# ===============================
# Broadcast listă utilizatori
# ===============================
async def broadcast_user_list():
    # Fiecărui client îi trimitem lista de CEILALȚI utilizatori (nu și pe el)
    for client_username, client_ws in user_connections.items():
        other_users = [u for u in user_connections.keys() if u != client_username]
        try:
            await client_ws.send(
                json.dumps({"type": "user_list", "users": other_users})
            )
        except Exception as e:
            print(f"Eroare la trimitere lista către {client_username}: {e}", flush=True)


# ===============================
# Main server
# ===============================
async def main():
    host = "0.0.0.0"  # Ascultă pe toate interfețele de rețea
    port = 8080  # Portul specificat de Fly.io

    print("=" * 50, flush=True)
    print("Server WebSocket pentru Chat Social", flush=True)
    print(f"Rulare pe: ws://{host}:{port}", flush=True)
    print("Ctrl+C pentru oprire", flush=True)
    print("=" * 50, flush=True)

    # Start WebSocket server și rulează infinit
    # Funcția process_request va gestiona health checks
    async with websockets.serve(
        handle_client, host, port, process_request=process_request
    ):
        print("[DEBUG] Server WebSocket pornit și ascultă conexiuni...", flush=True)
        # Ține serverul pornit
        await asyncio.Future()  # rulează infinit


# ===============================
# Start
# ===============================
if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nServer oprit.", flush=True)
