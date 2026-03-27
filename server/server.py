import asyncio
import json
import logging
import os
import re
import sqlite3
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Set, Tuple

from aiohttp import web

try:
    from google.auth.transport import requests as google_requests
    from google.oauth2 import id_token as google_id_token
except Exception:
    google_requests = None
    google_id_token = None


logging.getLogger("aiohttp.server").setLevel(logging.CRITICAL)


DB_PATH = os.environ.get(
    "CHAT_DB_PATH",
    os.path.join(os.path.dirname(__file__), "chat_history.db"),
)
GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID", "").strip()
HISTORY_LIMIT = int(os.environ.get("CHAT_HISTORY_LIMIT", "300"))
LOG_PATH = os.environ.get(
    "CHAT_LOG_PATH",
    os.path.join(os.path.dirname(__file__), "chat_server.log"),
)


connected_clients: Set[web.WebSocketResponse] = set()
user_connections: Dict[str, web.WebSocketResponse] = {}
groups: Dict[str, Set[str]] = {"General": set()}
group_creators: Dict[str, str] = {"General": "system"}


logger = logging.getLogger("chat_server")
if not logger.handlers:
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter(
        "%(asctime)s %(levelname)s %(name)s %(message)s"
    )

    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(formatter)
    logger.addHandler(stream_handler)

    try:
        file_handler = logging.FileHandler(LOG_PATH, encoding="utf-8")
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)
    except Exception as exc:
        logger.warning("Nu am putut deschide fișierul de log %s: %s", LOG_PATH, exc)


def log_event(event: str, **fields: Any) -> None:
    payload = {"event": event, **fields}
    logger.info(json.dumps(payload, ensure_ascii=False))


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def get_db_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db() -> None:
    with get_db_connection() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                username TEXT PRIMARY KEY,
                password TEXT,
                auth_provider TEXT NOT NULL DEFAULT 'password',
                google_sub TEXT UNIQUE,
                email TEXT UNIQUE,
                display_name TEXT,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS chat_groups (
                name TEXT PRIMARY KEY,
                creator TEXT NOT NULL,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS group_members (
                group_name TEXT NOT NULL,
                username TEXT NOT NULL,
                added_at TEXT NOT NULL,
                PRIMARY KEY (group_name, username),
                FOREIGN KEY(group_name) REFERENCES chat_groups(name) ON DELETE CASCADE,
                FOREIGN KEY(username) REFERENCES users(username) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                msg_type TEXT NOT NULL,
                sender TEXT NOT NULL,
                target TEXT,
                group_name TEXT,
                message TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                FOREIGN KEY(sender) REFERENCES users(username) ON DELETE SET NULL
            );

            CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);
            CREATE INDEX IF NOT EXISTS idx_messages_group ON messages(group_name);
            CREATE INDEX IF NOT EXISTS idx_messages_target ON messages(target);
            """
        )

        now = utc_now_iso()
        conn.execute(
            """
            INSERT OR IGNORE INTO chat_groups(name, creator, created_at)
            VALUES('General', 'system', ?)
            """,
            (now,),
        )


def load_credentials(file_path: str) -> Dict[str, str]:
    credentials: Dict[str, str] = {}
    source_path = file_path

    if not os.path.exists(source_path):
        source_path = os.path.join(os.path.dirname(__file__), "password.txt")

    if os.path.exists(source_path):
        with open(source_path, "r", encoding="utf-8") as file:
            for raw_line in file:
                parts = raw_line.strip().split(":")
                if len(parts) != 2:
                    continue
                username = parts[0].strip()
                password = parts[1].strip()
                if username:
                    credentials[username] = password
    else:
        credentials["1"] = "1"
        credentials["2"] = "2"

    print(f"[DEBUG] Credentials loaded: {len(credentials)} users", flush=True)
    return credentials


def sync_password_users(credentials: Dict[str, str]) -> None:
    now = utc_now_iso()
    with get_db_connection() as conn:
        for username, password in credentials.items():
            conn.execute(
                """
                INSERT INTO users(username, password, auth_provider, created_at)
                VALUES(?, ?, 'password', ?)
                ON CONFLICT(username) DO UPDATE SET
                    password=excluded.password,
                    auth_provider='password'
                """,
                (username, password, now),
            )


def refresh_group_state() -> None:
    global groups, group_creators

    loaded_groups: Dict[str, Set[str]] = {}
    loaded_creators: Dict[str, str] = {}
    with get_db_connection() as conn:
        group_rows = conn.execute(
            "SELECT name, creator FROM chat_groups"
        ).fetchall()
        for row in group_rows:
            group_name = row["name"]
            loaded_groups[group_name] = set()
            loaded_creators[group_name] = row["creator"] or "system"

        member_rows = conn.execute(
            "SELECT group_name, username FROM group_members"
        ).fetchall()
        for row in member_rows:
            group_name = row["group_name"]
            username = row["username"]
            loaded_groups.setdefault(group_name, set()).add(username)

    loaded_groups.setdefault("General", set())
    loaded_creators.setdefault("General", "system")

    groups = loaded_groups
    group_creators = loaded_creators


def user_exists(username: str) -> bool:
    with get_db_connection() as conn:
        row = conn.execute(
            "SELECT 1 FROM users WHERE username = ? LIMIT 1", (username,)
        ).fetchone()
        return row is not None


def verify_password_auth(username: str, password: str) -> bool:
    with get_db_connection() as conn:
        row = conn.execute(
            """
            SELECT 1 FROM users
            WHERE username = ? AND auth_provider = 'password' AND password = ?
            LIMIT 1
            """,
            (username, password),
        ).fetchone()
        return row is not None


def register_password_user(username: str, password: str) -> Tuple[bool, str]:
    username = username.strip()
    password = password.strip()

    if not username or not password:
        return False, "Username și parola sunt obligatorii."
    if len(username) < 3:
        return False, "Username-ul trebuie să aibă minim 3 caractere."
    if len(password) < 4:
        return False, "Parola trebuie să aibă minim 4 caractere."
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", username):
        return False, "Username-ul poate conține doar litere, cifre, . _ -"

    with get_db_connection() as conn:
        existing = conn.execute(
            "SELECT auth_provider FROM users WHERE username = ? LIMIT 1",
            (username,),
        ).fetchone()
        if existing:
            provider = (existing["auth_provider"] or "").strip()
            if provider == "google":
                return (
                    False,
                    "Username-ul există deja și este asociat autentificării Google.",
                )
            return False, "Username-ul există deja."

        conn.execute(
            """
            INSERT INTO users(username, password, auth_provider, created_at)
            VALUES(?, ?, 'password', ?)
            """,
            (username, password, utc_now_iso()),
        )

    return True, "Cont creat cu succes."


def ensure_user_in_general(username: str) -> None:
    if not user_exists(username):
        return
    with get_db_connection() as conn:
        conn.execute(
            """
            INSERT OR IGNORE INTO group_members(group_name, username, added_at)
            VALUES('General', ?, ?)
            """,
            (username, utc_now_iso()),
        )


def save_message(
    msg_type: str,
    sender: str,
    message: str,
    *,
    target: Optional[str] = None,
    group_name: Optional[str] = None,
    timestamp: Optional[str] = None,
) -> str:
    ts = timestamp or utc_now_iso()
    with get_db_connection() as conn:
        conn.execute(
            """
            INSERT INTO messages(msg_type, sender, target, group_name, message, timestamp)
            VALUES(?, ?, ?, ?, ?, ?)
            """,
            (msg_type, sender, target, group_name, message, ts),
        )
    return ts


def generate_username_from_email(email: str) -> str:
    base = email.split("@")[0].strip().lower()
    base = re.sub(r"[^a-z0-9_.-]", "_", base).strip("._-")
    if not base:
        base = "user"

    candidate = base
    suffix = 2
    while user_exists(candidate):
        candidate = f"{base}_{suffix}"
        suffix += 1
    return candidate


def verify_google_token(id_token_value: str) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    if not id_token_value:
        return None, "Token Google lipsă."
    if google_requests is None or google_id_token is None:
        return None, "Lipsește pachetul google-auth pe server."
    if not GOOGLE_CLIENT_ID:
        return None, "Serverul nu are GOOGLE_CLIENT_ID configurat."

    try:
        request_adapter = google_requests.Request()
        payload = google_id_token.verify_oauth2_token(
            id_token_value,
            request_adapter,
            audience=GOOGLE_CLIENT_ID,
        )
        email = (payload.get("email") or "").strip().lower()
        sub = (payload.get("sub") or "").strip()
        if not email or not sub:
            return None, "Token Google invalid (email/sub lipsă)."
        return payload, None
    except Exception as exc:
        return None, f"Token Google invalid: {exc}"


def upsert_google_user(payload: Dict[str, Any]) -> str:
    email = (payload.get("email") or "").strip().lower()
    sub = (payload.get("sub") or "").strip()
    display_name = (payload.get("name") or email.split("@")[0]).strip()
    now = utc_now_iso()

    with get_db_connection() as conn:
        existing = conn.execute(
            "SELECT username FROM users WHERE google_sub = ? OR email = ? LIMIT 1",
            (sub, email),
        ).fetchone()

        if existing:
            username = existing["username"]
            conn.execute(
                """
                UPDATE users
                SET auth_provider='google',
                    google_sub=?,
                    email=?,
                    display_name=?
                WHERE username=?
                """,
                (sub, email, display_name, username),
            )
            return username

        username = generate_username_from_email(email)
        conn.execute(
            """
            INSERT INTO users(username, auth_provider, google_sub, email, display_name, created_at)
            VALUES(?, 'google', ?, ?, ?, ?)
            """,
            (username, sub, email, display_name, now),
        )
        return username


def build_history_payload(username: str) -> Dict[str, Any]:
    user_groups = set()
    user_groups.add("General")

    with get_db_connection() as conn:
        group_rows = conn.execute(
            "SELECT group_name FROM group_members WHERE username = ?",
            (username,),
        ).fetchall()
        for row in group_rows:
            user_groups.add(row["group_name"])

        db_messages = conn.execute(
            """
            SELECT id, msg_type, sender, target, group_name, message, timestamp
            FROM messages
            ORDER BY id DESC
            LIMIT ?
            """,
            (HISTORY_LIMIT,),
        ).fetchall()

    history: List[Dict[str, Any]] = []
    for row in reversed(db_messages):
        msg_type = row["msg_type"]
        sender = row["sender"]
        target = row["target"]
        group_name = row["group_name"]

        is_allowed = False
        is_private = False
        payload_group: Optional[str] = None
        payload_target: Optional[str] = None

        if msg_type == "public":
            is_allowed = True
            payload_group = "General"
        elif msg_type == "private":
            is_private = True
            if sender == username or target == username:
                is_allowed = True
                payload_target = target
        elif msg_type == "group":
            if group_name and group_name in user_groups:
                is_allowed = True
                payload_group = group_name

        if not is_allowed:
            continue

        history.append(
            {
                "username": sender,
                "message": row["message"],
                "timestamp": row["timestamp"],
                "is_private": is_private,
                "group": payload_group,
                "target": payload_target,
            }
        )

    payload_group_members = {
        group_name: sorted(list(members))
        for group_name, members in groups.items()
        if group_name in user_groups
    }
    payload_creators = {
        group_name: creator
        for group_name, creator in group_creators.items()
        if group_name in user_groups
    }

    return {
        "type": "history",
        "messages": history,
        "groups": sorted(list(user_groups)),
        "group_creators": payload_creators,
        "group_members": payload_group_members,
    }


async def safe_send(ws: web.WebSocketResponse, payload: Dict[str, Any]) -> None:
    try:
        await ws.send_str(json.dumps(payload))
    except Exception as exc:
        print(f"[DEBUG] send failed: {exc}", flush=True)


async def broadcast_message(
    payload: Dict[str, Any],
    exclude_ws: Optional[web.WebSocketResponse] = None,
) -> None:
    if not connected_clients:
        return
    targets = [ws for ws in connected_clients if ws is not exclude_ws]
    if not targets:
        return
    raw = json.dumps(payload)
    await asyncio.gather(
        *[ws.send_str(raw) for ws in targets],
        return_exceptions=True,
    )


async def broadcast_user_list() -> None:
    usernames = list(user_connections.keys())
    for current_username, current_ws in list(user_connections.items()):
        others = [u for u in usernames if u != current_username]
        await safe_send(current_ws, {"type": "user_list", "users": others})


async def websocket_handler(request: web.Request) -> web.WebSocketResponse:
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    connected_clients.add(ws)
    username: Optional[str] = None

    await safe_send(ws, {"type": "welcome", "message": "Conectat la server"})
    log_event("ws_connected", remote=request.remote)

    try:
        async for incoming in ws:
            if incoming.type != web.WSMsgType.TEXT:
                continue

            try:
                data = json.loads(incoming.data)
            except json.JSONDecodeError:
                continue

            msg_type = (data.get("type") or "").strip()
            if not msg_type:
                continue

            if msg_type == "auth":
                attempted_user = (data.get("username") or "").strip()
                attempted_pass = (data.get("password") or "").strip()
                if verify_password_auth(attempted_user, attempted_pass):
                    username = attempted_user
                    user_connections[username] = ws
                    ensure_user_in_general(username)
                    refresh_group_state()
                    await safe_send(
                        ws,
                        {
                            "type": "auth_success",
                            "message": "Autentificare reușită",
                            "username": username,
                            "auth_provider": "password",
                        },
                    )
                    await broadcast_user_list()
                    log_event(
                        "auth_success",
                        method="password",
                        username=username,
                        remote=request.remote,
                    )
                else:
                    await safe_send(
                        ws,
                        {
                            "type": "auth_error",
                            "message": "Username sau parolă greșită",
                        },
                    )
                    log_event(
                        "auth_error",
                        method="password",
                        username=attempted_user,
                        reason="invalid_credentials",
                        remote=request.remote,
                    )
                continue

            if msg_type == "register":
                attempted_user = (data.get("username") or "").strip()
                attempted_pass = (data.get("password") or "").strip()
                ok, message = register_password_user(attempted_user, attempted_pass)
                if ok:
                    username = attempted_user
                    user_connections[username] = ws
                    ensure_user_in_general(username)
                    refresh_group_state()
                    await safe_send(
                        ws,
                        {
                            "type": "auth_success",
                            "message": message,
                            "username": username,
                            "auth_provider": "password",
                            "registered": True,
                        },
                    )
                    await broadcast_user_list()
                    log_event(
                        "register_success",
                        username=username,
                        remote=request.remote,
                    )
                else:
                    await safe_send(
                        ws,
                        {
                            "type": "auth_error",
                            "message": message,
                        },
                    )
                    log_event(
                        "register_error",
                        username=attempted_user,
                        reason=message,
                        remote=request.remote,
                    )
                continue

            if msg_type == "google_auth":
                token_value = (data.get("id_token") or "").strip()
                log_event(
                    "google_auth_attempt",
                    remote=request.remote,
                    token_present=bool(token_value),
                )
                payload, error = verify_google_token(token_value)
                if error:
                    await safe_send(ws, {"type": "auth_error", "message": error})
                    log_event(
                        "auth_error",
                        method="google",
                        reason=error,
                        remote=request.remote,
                    )
                    continue

                username = upsert_google_user(payload or {})
                ensure_user_in_general(username)
                refresh_group_state()
                user_connections[username] = ws
                await safe_send(
                    ws,
                    {
                        "type": "auth_success",
                        "message": "Autentificare Google reușită",
                        "username": username,
                        "auth_provider": "google",
                    },
                )
                await broadcast_user_list()
                log_event(
                    "auth_success",
                    method="google",
                    username=username,
                    remote=request.remote,
                )
                continue

            if not username:
                await safe_send(
                    ws,
                    {"type": "auth_error", "message": "Trebuie autentificare."},
                )
                continue

            if msg_type == "request_history":
                await safe_send(ws, build_history_payload(username))
                continue

            if msg_type == "request_user_list":
                others = [u for u in user_connections.keys() if u != username]
                await safe_send(ws, {"type": "user_list", "users": others})
                continue

            if msg_type == "ping":
                await safe_send(ws, {"type": "pong", "timestamp": utc_now_iso()})
                continue

            if msg_type == "logout":
                break

            if msg_type == "message":
                msg_text = (data.get("message") or "").strip()
                if not msg_text:
                    continue
                ts = save_message("public", username, msg_text, group_name="General")
                await broadcast_message(
                    {
                        "type": "message",
                        "username": username,
                        "message": msg_text,
                        "timestamp": ts,
                    }
                )
                continue

            if msg_type == "private_message":
                target = (data.get("target") or "").strip()
                msg_text = (data.get("message") or "").strip()
                if not target or not msg_text:
                    continue

                ts = save_message(
                    "private",
                    username,
                    msg_text,
                    target=target,
                )
                if target in user_connections:
                    await safe_send(
                        user_connections[target],
                        {
                            "type": "private_message",
                            "username": username,
                            "target": target,
                            "message": msg_text,
                            "timestamp": ts,
                        },
                    )
                else:
                    await safe_send(
                        ws,
                        {
                            "type": "error",
                            "message": f"Utilizatorul {target} nu este conectat",
                        },
                    )
                continue

            if msg_type == "create_group":
                group_name = (data.get("group_name") or "").strip()
                if not group_name:
                    await safe_send(
                        ws,
                        {"type": "error", "message": "Numele grupului este gol."},
                    )
                    continue
                if group_name in groups:
                    await safe_send(
                        ws,
                        {"type": "error", "message": "Grupul există deja."},
                    )
                    continue

                with get_db_connection() as conn:
                    conn.execute(
                        """
                        INSERT INTO chat_groups(name, creator, created_at)
                        VALUES(?, ?, ?)
                        """,
                        (group_name, username, utc_now_iso()),
                    )
                    conn.execute(
                        """
                        INSERT OR IGNORE INTO group_members(group_name, username, added_at)
                        VALUES(?, ?, ?)
                        """,
                        (group_name, username, utc_now_iso()),
                    )
                refresh_group_state()

                await safe_send(
                    ws,
                    {
                        "type": "group_created",
                        "group_name": group_name,
                        "creator": username,
                    },
                )
                await broadcast_message(
                    {
                        "type": "group_created",
                        "group_name": group_name,
                        "creator": username,
                    },
                    exclude_ws=ws,
                )
                continue

            if msg_type == "add_to_group":
                group_name = (data.get("group_name") or "").strip()
                member = (data.get("member") or "").strip()
                if not group_name or not member:
                    continue
                if group_name not in groups:
                    await safe_send(
                        ws,
                        {"type": "error", "message": f"Grupul {group_name} nu există."},
                    )
                    continue
                if username not in groups[group_name]:
                    await safe_send(
                        ws,
                        {"type": "error", "message": "Nu ai acces la acest grup."},
                    )
                    continue
                if not user_exists(member):
                    await safe_send(
                        ws,
                        {"type": "error", "message": f"Utilizatorul {member} nu există."},
                    )
                    continue

                with get_db_connection() as conn:
                    conn.execute(
                        """
                        INSERT OR IGNORE INTO group_members(group_name, username, added_at)
                        VALUES(?, ?, ?)
                        """,
                        (group_name, member, utc_now_iso()),
                    )
                refresh_group_state()

                payload = {
                    "type": "added_to_group",
                    "group_name": group_name,
                    "member": member,
                }
                await safe_send(ws, payload)
                if member in user_connections:
                    await safe_send(user_connections[member], payload)
                continue

            if msg_type == "remove_from_group":
                group_name = (data.get("group_name") or "").strip()
                member = (data.get("member") or "").strip()
                if not group_name or not member:
                    continue
                if group_name not in groups:
                    continue
                creator = group_creators.get(group_name, "")
                if username != creator:
                    await safe_send(
                        ws,
                        {"type": "error", "message": "Doar creatorul poate elimina membri."},
                    )
                    continue
                if member == creator:
                    await safe_send(
                        ws,
                        {"type": "error", "message": "Creatorul nu poate fi eliminat."},
                    )
                    continue

                with get_db_connection() as conn:
                    conn.execute(
                        "DELETE FROM group_members WHERE group_name = ? AND username = ?",
                        (group_name, member),
                    )
                refresh_group_state()

                payload = {
                    "type": "removed_from_group",
                    "group_name": group_name,
                    "member": member,
                }
                await safe_send(ws, payload)
                if member in user_connections:
                    await safe_send(user_connections[member], payload)
                    await safe_send(
                        user_connections[member],
                        {
                            "type": "private_message",
                            "username": username,
                            "target": member,
                            "message": f"__REMOVED_FROM_GROUP::{group_name}",
                            "timestamp": utc_now_iso(),
                        },
                    )
                continue

            if msg_type == "delete_group":
                group_name = (data.get("group_name") or "").strip()
                if not group_name or group_name == "General":
                    continue
                if group_name not in groups:
                    continue
                creator = group_creators.get(group_name, "")
                if creator != username:
                    await safe_send(
                        ws,
                        {"type": "error", "message": "Doar creatorul poate șterge grupul."},
                    )
                    continue

                impacted_members = list(groups.get(group_name, set()))
                with get_db_connection() as conn:
                    conn.execute("DELETE FROM messages WHERE group_name = ?", (group_name,))
                    conn.execute("DELETE FROM chat_groups WHERE name = ?", (group_name,))
                refresh_group_state()

                await broadcast_message(
                    {
                        "type": "group_deleted",
                        "group_name": group_name,
                    }
                )
                for member in impacted_members:
                    if member == username:
                        continue
                    if member in user_connections:
                        await safe_send(
                            user_connections[member],
                            {
                                "type": "private_message",
                                "username": username,
                                "target": member,
                                "message": f"__DELETED_GROUP::{group_name}",
                                "timestamp": utc_now_iso(),
                            },
                        )
                continue

            if msg_type == "group_message":
                group_name = (data.get("group") or "").strip()
                msg_text = (data.get("message") or "").strip()
                if not group_name or not msg_text:
                    continue
                if group_name not in groups or username not in groups[group_name]:
                    await safe_send(
                        ws,
                        {"type": "error", "message": "Nu ai acces la acest grup."},
                    )
                    continue

                ts = save_message(
                    "group",
                    username,
                    msg_text,
                    group_name=group_name,
                )
                for member in groups[group_name]:
                    if member in user_connections:
                        await safe_send(
                            user_connections[member],
                            {
                                "type": "group_message",
                                "username": username,
                                "group": group_name,
                                "message": msg_text,
                                "timestamp": ts,
                            },
                        )
                continue

            if msg_type == "typing":
                target = (data.get("target") or "").strip()
                is_typing = bool(data.get("typing", False))
                if target in user_connections:
                    await safe_send(
                        user_connections[target],
                        {
                            "type": "typing",
                            "username": username,
                            "target": target,
                            "typing": is_typing,
                        },
                    )
                continue

    except Exception as exc:
        logger.exception("WS handler exception: %s", exc)
    finally:
        connected_clients.discard(ws)
        if username and user_connections.get(username) is ws:
            del user_connections[username]
            await broadcast_user_list()
        log_event("ws_disconnected", username=(username or "anonymous"))

    return ws


async def health_check(_: web.Request) -> web.Response:
    return web.json_response(
        {
            "status": "ok",
            "service": "chat-social-server",
            "db_path": DB_PATH,
            "google_auth_enabled": bool(GOOGLE_CLIENT_ID),
        }
    )


async def main() -> None:
    port = int(os.environ.get("PORT", "10000"))
    host = "0.0.0.0"

    init_db()
    credentials = load_credentials("/etc/secrets/password.txt")
    sync_password_users(credentials)
    refresh_group_state()

    print("=" * 60)
    print("Server Chat Social")
    print(f"WebSocket: ws://{host}:{port}/ws")
    print(f"Health:    http://{host}:{port}/")
    print(f"DB:        {DB_PATH}")
    print(f"GoogleAuth:{'ON' if GOOGLE_CLIENT_ID else 'OFF'}")
    print("=" * 60)

    app = web.Application()
    app.router.add_get("/", health_check)
    app.router.add_get("/ws", websocket_handler)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, host, port)
    await site.start()

    try:
        await asyncio.Future()
    finally:
        await runner.cleanup()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nServer oprit.", flush=True)
