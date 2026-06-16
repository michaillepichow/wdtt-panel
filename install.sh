#!/bin/bash

# Скрипт автоматической установки WDTT VPN из репозитория
if [ "$EUID" -ne 0 ]; then
  echo -e "\e[31mОшибка: Запустите скрипт от имени root (через sudo).\e[0m"
  exit 1
fi

if [ ! -f "./wdtt-server" ]; then
  echo -e "\e[31mОшибка: Исполняемый файл wdtt-server не найден в текущей папке установки!\e[0m"
  exit 1
fi

SERVER_IP=$(curl -s https://icanhazip.com || echo "your-server-ip")

echo "=== Установка WDTT VPN (из репозитория) ==="
read -p "Логин администратора веб-панели [default: admin]: " PANEL_USER
PANEL_USER=${PANEL_USER:-admin}

DEFAULT_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)
read -p "Пароль веб-панели [default: $DEFAULT_PASS]: " PANEL_PASS
PANEL_PASS=${PANEL_PASS:-$DEFAULT_PASS}

read -p "Порт веб-панели [default: 8080]: " PANEL_PORT
PANEL_PORT=${PANEL_PORT:-8080}

read -p "UDP-порт для DTLS [default: 56000]: " DTLS_PORT
DTLS_PORT=${DTLS_PORT:-56000}

read -p "Внутренний порт WireGuard [default: 56001]: " WG_PORT
WG_PORT=${WG_PORT:-56001}

read -p "Локальный порт клиента (TUN) [default: 9000]: " TUN_PORT
TUN_PORT=${TUN_PORT:-9000}

# Установка зависимостей
echo "[1/6] Установка пакетов системы..."
apt-get update
apt-get install -y python3 python3-pip python3-venv iptables curl jq iptables-persistent

# Копирование готового бинарника в систему
echo "[2/6] Копирование исполняемого файла ядра..."
cp ./wdtt-server /usr/local/bin/wdtt-server
chmod +x /usr/local/bin/wdtt-server

# Создание служебных директорий
echo "[3/6] Настройка служебных папок и базы данных..."
mkdir -p /etc/wdtt
mkdir -p /opt/wdtt-panel

if [ ! -f /etc/wdtt/passwords.json ]; then
  MAIN_DB_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
  cat <<DB_EOF > /etc/wdtt/passwords.json
{
    "main_password": "$MAIN_DB_PASS",
    "admin_id": "",
    "bot_token": "",
    "passwords": {},
    "devices": {}
}
DB_EOF
fi

# Конфигурация ядра и NAT сети
echo "[4/6] Настройка sysctl и NAT..."
cp 99-wdtt.conf /etc/sysctl.d/99-wdtt.conf
sysctl -p /etc/sysctl.d/99-wdtt.conf

MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -n "$MAIN_IFACE" ]; then
  iptables -t nat -A POSTROUTING -o "$MAIN_IFACE" -j MASQUERADE
  netfilter-persistent save
fi

# Настройка веб-панели управления
echo "[5/6] Создание окружения Python..."
cp app.py /opt/wdtt-panel/app.py
sed -i "s/56000,56001,9000/${DTLS_PORT},${WG_PORT},${TUN_PORT}/g" /opt/wdtt-panel/app.py

python3 -m venv /opt/wdtt-panel/venv
/opt/wdtt-panel/venv/bin/pip install --upgrade pip
/opt/wdtt-panel/venv/bin/pip install flask werkzeug

# Настройка системных служб systemd из шаблонов
echo "[6/6] Установка служб Systemd..."
sed "s/{{PANEL_USER}}/${PANEL_USER}/g; s/{{PANEL_PASS}}/${PANEL_PASS}/g; s/{{PANEL_PORT}}/${PANEL_PORT}/g" wdtt-panel.service.template > /etc/systemd/system/wdtt-panel.service
sed "s/{{DTLS_PORT}}/${DTLS_PORT}/g; s/{{WG_PORT}}/${WG_PORT}/g" wdtt-vpn.service.template > /etc/systemd/system/wdtt-vpn.service

systemctl daemon-reload
systemctl enable --now wdtt-panel
systemctl enable --now wdtt-vpn

echo "=================================================="
echo "Установка успешно завершена!"
echo "Панель управления доступна по адресу:"
echo "http://$SERVER_IP:$PANEL_PORT"
echo "Учетные данные: $PANEL_USER / $PANEL_PASS"
echo "=================================================="
