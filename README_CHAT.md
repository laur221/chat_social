# Chat Social - Aplicație de Chat în Timp Real

## Descriere
Aplicație de chat completă cu autentificare, mesagerie privată și grupuri, separată în fișiere distincte pentru o mai bună organizare.

## Funcționalități

### Fereastra de Login
- Dimensiune mică: 500x350 pixeli
- Autentificare cu nume de utilizator și parolă
- Verificare în fișierul `lib/password.txt`
- Interfață curată și simplă

### Fereastra de Chat
- Dimensiune mare: minim 1200x800 pixeli (se schimbă automat după login)
- **Panou Stâng (280px):**
  - Numele utilizatorului curent
  - Lista grupurilor existente
  - Buton "Creează grup" pentru a crea grupuri noi
  - Lista utilizatorilor conectați în timp real
  - Click pe utilizator pentru chat privat
- **Panou Drept:**
  - Header cu numele chat-ului selectat
  - Lista mesajelor cu bubble-uri colorate
  - Numele expeditorului la fiecare mesaj
  - Timestamp pentru fiecare mesaj
  - Input pentru mesaje noi
  - Buton Send

### Server WebSocket (Python)
- Serverul rulează pe portul 8080
- Gestionare conexiuni în timp real
- Broadcast mesaje către toți utilizatorii
- Mesagerie privată
- Creare grupuri
- Lista utilizatorilor conectați

## Structura Fișierelor

```
chat_social/
├── server.py               # Server WebSocket (Python)
├── start_server.bat        # Script de pornire server
├── requirements.txt       # Dependințe Python
├── lib/
│   ├── main.dart          # Punctul de intrare principal
│   ├── windows/
│   │   ├── main.dart      # Entry point Windows
│   │   ├── login.dart     # Ecran de login
│   │   └── chat.dart      # Ecran de chat
│   ├── android/
│   │   └── main.dart      # Aplicația Android
│   └── password.txt       # Fișierul cu utilizatori și parole
└── pubspec.yaml          # Dependințe Flutter
```

## Cum să rulezi aplicația

### Pasul 1: Pornește Serverul Python

**Opțiunea A - Cu fișier batch:**
Dublează click pe `start_server.bat` sau rulează:
```bash
start_server.bat
```

**Opțiunea B - Manual:**
Într-un terminal, rulează:
```bash
python server.py
```

Serverul va porni pe `ws://localhost:8080`

Vezi mesajul: "Server pornit cu succes! Aștept conexiuni..."

### Pasul 2: Rulează Aplicația Flutter
Într-un alt terminal, rulează:
```bash
flutter run -d windows
```

Aplicația se va conecta automat la `ws://localhost:8080`

## Fișierul de Utilizatori
Creează fișierul `lib/password.txt` cu următorul format:
```
user1:parola1
user2:parola2
admin:admin123
```

## Fluxul de Utilizare

1. Deschide aplicația pe mai multe ferestre/instanțe
2. Autentifică-te cu utilizatori diferiți
3. Vezi toți utilizatorii conectați în panoul stâng
4. Click pe un utilizator pentru chat privat
5. Click pe "Creează grup" pentru a crea un grup nou
6. Scrie mesaje în zona de input și apasă Enter sau butonul Send

## Dependențe

### Client (Flutter)
- `flutter` - Framework-ul principal
- `window_size` - Control dimensiune fereastră
- `web_socket_channel` - Comunicare WebSocket

### Server (Python)
- `python3` - Python 3.x
- `websockets` - Bibliotecă WebSocket pentru Python

### Instalare dependențe Python
```bash
pip install websockets
```

## Caracteristici Tehnice

### Organizare Cod
- **Fișiere separate**: Login și Chat sunt în fișiere distincte
- **Modularitate**: Fiecare ecran este independent și reutilizabil
- **Mentenabilitate**: Codul este organizat și ușor de întreținut

### Funcționalități
- WebSocket pentru comunicare în timp real
- StatefulWidget pentru managementul stării
- TextEditingController pentru input-uri
- Separare clară între login și chat
- Navigare între pagini cu Navigator
- Design modern cu culori armonioase
- Dimensiune fereastră adaptivă

## Reparări Implementate

✅ Eroare TypeError în server.py (parametrul `path` adăugat)
✅ Separare login și chat în fișiere diferite
✅ Dimensiune fereastră chat mărită la 1200x800
✅ Importuri corecte între fișiere
