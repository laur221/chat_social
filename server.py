import asyncio
import websockets
import json
from datetime import datetime
from typing import Set, Dict
from websockets.server import WebSocketServer
import os

# ===============================
# Stocare conexiuni
# ===============================
connected_clients: Set[WebSocketServer] = set()
user_connections: Dict[str, WebSocketServer] = {}
# Grupele cu membrii lor: {nume_grup: [nume_utilizator1, nume_utilizator2, ...]}
groups: Dict[str, Set[str]] = {"General": set()}

# ===============================
# Încarcă utilizatorii și parolele din fișier
# ===============================
def load_credentials(file_path):
    credentials = {}
    if os.path.exists(file_path):
        with open(file_path, 'r') as file:
            for line in file:
                parts = line.strip().split(':')
                if len(parts) == 2:
                    username, password = parts
                    credentials[username] = password
    return credentials

user_credentials = load_credentials('password.txt')

# ===============================
# Autentificare pe server (mutată în handle_client)
# ===============================
async def handle_client(websocket: WebSocketServer):
    print(f"Client conectat. Total clienți: {len(connected_clients) + 1}")

    connected_clients.add(websocket)
    username = None

    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                msg_type = data.get("type")

                # =========================
                # Autentificare
                # =========================
                if msg_type == "auth":
                    username = data.get("username")
                    password = data.get("password")

                    # Verifică utilizatorul și parola
                    if username in user_credentials and user_credentials[username] == password:
                        user_connections[username] = websocket
                        await websocket.send(json.dumps({
                            "type": "auth_success",
                            "message": "Autentificare reușită"
                        }))
                        print(f"Utilizator autentificat: {username}")
                    else:
                        await websocket.send(json.dumps({
                            "type": "auth_error",
                            "message": "Nume de utilizator sau parolă greșită"
                        }))

                # =========================
                # Typing indicator
                # =========================
                elif msg_type == "typing" and username:
                    target = data.get("target")
                    is_typing = data.get("typing", True)
                    
                    # Trimite indicatorul de typing către destinatar
                    if target in user_connections and target != username:
                        await user_connections[target].send(json.dumps({
                            "type": "typing",
                            "username": username,
                            "typing": is_typing,
                            "target": target
                        }))
                
                # =========================
                # Mesaj public (Chat General)
                # =========================
                elif msg_type == "message" and username:
                    msg_text = data.get("message", "")

                    await broadcast_message({
                        "type": "message",
                        "username": username,
                        "message": msg_text,
                        "timestamp": datetime.now().isoformat()
                    })

                    print(f"{username}: {msg_text}")

                # =========================
                # Mesaj în grup
                # =========================
                elif msg_type == "group_message" and username:
                    group_name = data.get("group")
                    msg_text = data.get("message", "")

                    if group_name in groups:
                        group_members = groups[group_name]
                        msg_json = json.dumps({
                            "type": "group_message",
                            "username": username,
                            "group": group_name,
                            "message": msg_text,
                            "timestamp": datetime.now().isoformat()
                        })
                        
                        # Trimite mesajul către toți membrii grupului
                        for member in group_members:
                            if member in user_connections:
                                try:
                                    await user_connections[member].send(msg_json)
                                except Exception as e:
                                    print(f"Eroare la trimitere mesaj grup către {member}: {e}")
                        print(f"{username} în grupul {group_name}: {msg_text}")

                # =========================
                # Mesaj privat
                # =========================
                elif msg_type == "private_message" and username:
                    target = data.get("target")
                    msg_text = data.get("message", "")

                    if target in user_connections:
                        await user_connections[target].send(json.dumps({
                            "type": "private_message",
                            "username": username,
                            "target": target,
                            "message": msg_text,
                            "timestamp": datetime.now().isoformat()
                        }))

                        print(f"PM {username} -> {target}")

                # =========================
                # Creare grup
                # =========================
                elif msg_type == "create_group" and username:
                    group_name = data.get("group_name")

                    if group_name and group_name not in groups:
                        groups[group_name] = {username}  # Creatorul este primul membru
                        await broadcast_message({
                            "type": "group_created",
                            "group_name": group_name,
                            "creator": username,
                            "timestamp": datetime.now().isoformat()
                        })
                        print(f"Grup creat: {group_name} de {username}")

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
                            await user_connections[member_to_add].send(json.dumps({
                                "type": "added_to_group",
                                "group_name": group_name,
                                "added_by": username
                            }))
                            print(f"{member_to_add} adăugat în grupul {group_name} de {username}")

            except json.JSONDecodeError:
                print("Mesaj JSON invalid")

    except websockets.exceptions.ConnectionClosed:
        print(f"Client deconectat: {username}")

    finally:
        # Curățare la deconectare
        connected_clients.discard(websocket)

        if username and username in user_connections:
            del user_connections[username]
            # Șterge utilizatorul din toate grupurile
            for group_name in groups:
                if username in groups[group_name]:
                    groups[group_name].discard(username)
            print(f"Utilizator șters: {username}")
            await broadcast_user_list()


# ===============================
# Broadcast mesaje
# ===============================
async def broadcast_message(message: dict):
    if not connected_clients:
        return

    msg = json.dumps(message)
    await asyncio.gather(
        *[client.send(msg) for client in connected_clients],
        return_exceptions=True
    )


# ===============================
# Broadcast listă utilizatori
# ===============================
async def broadcast_user_list():
    # Fiecărui client îi trimitem lista de CEILALȚI utilizatori (nu și pe el)
    for client_username, client_ws in user_connections.items():
        other_users = [u for u in user_connections.keys() if u != client_username]
        try:
            await client_ws.send(json.dumps({
                "type": "user_list",
                "users": other_users
            }))
        except Exception as e:
            print(f"Eroare la trimitere lista către {client_username}: {e}")


# ===============================
# Main server
# ===============================
async def main():
    host = "0.0.0.0"  # Ascultă pe toate interfețele de rețea
    port = 8080

    print("=" * 50)
    print("Server WebSocket pentru Chat Social")
    print(f"Rulare pe: ws://{host}:{port}")
    print("Ctrl+C pentru oprire")
    print("=" * 50)

    async with websockets.serve(handle_client, host, port):
        print("Server pornit cu succes! Aștept conexiuni...")
        await asyncio.Future()  # rulează infinit


# ===============================
# Start
# ===============================
if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nServer oprit.")
