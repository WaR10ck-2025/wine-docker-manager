FROM ubuntu:22.04

# Verhindert interaktive Prompts während apt-install
ENV DEBIAN_FRONTEND=noninteractive

# 32-bit Multiarch + WineHQ-Repository (Wine 9.x statt Ubuntu 6.x)
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        curl wget ca-certificates gnupg \
    && mkdir -pm755 /etc/apt/keyrings && \
    curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
        | gpg --dearmor -o /etc/apt/keyrings/winehq.gpg && \
    echo "deb [arch=amd64,i386 signed-by=/etc/apt/keyrings/winehq.gpg] https://dl.winehq.org/wine-builds/ubuntu/ jammy main" \
        > /etc/apt/sources.list.d/winehq.list && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable && \
    apt-get install -y --no-install-recommends \
        # GUI / VNC Stack
        xvfb x11vnc \
        # noVNC + WebSocket-Proxy
        novnc websockify python3 \
        # Wine-Hilfswerkzeuge
        winetricks cabextract \
        # USB (libusb für WINEUSB)
        libusb-1.0-0 \
        # Basis-Tools
        bash \
    && rm -rf /var/lib/apt/lists/*

# Non-Root User anlegen
RUN useradd -m -u 1000 -s /bin/bash wineuser

# Verzeichnisse anlegen
RUN mkdir -p /uploads /app && chown -R wineuser:wineuser /uploads /app

# Startskript einbinden
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Als root starten — start.sh korrigiert Volume-Ownership und wechselt zu wineuser
USER root

# Wine-Umgebung konfigurieren
ENV WINEARCH=win64
ENV WINEPREFIX=/home/wineuser/.wine
ENV DISPLAY=:99
ENV WINEDEBUG=-all

# Ports: 5900 = VNC direkt, 8080 = noVNC Browser
EXPOSE 5900 8080

ENTRYPOINT ["/start.sh"]
