# Folosim imagine oficială Python
FROM python:3.12-slim

# Setăm directorul de lucru
WORKDIR /app

# Copiem fișierele necesare
COPY . .

# Instalăm dependențele
RUN pip install --no-cache-dir -r requirements.txt

# Expunem porturile serverului
EXPOSE 8080 2910

# Comanda pentru rulare
CMD ["python", "server.py"]
