#!/bin/bash

# Цветовая палитра для вывода
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
NC='\e[0m' # No Color

# --- ПРОВЕРКИ ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Запустите скрипт от имени root (через sudo).${NC}"
  exit 1
fi

if [ ! -f "./wdtt-server" ]; then
  echo -e "${RED}Ошибка: Исполняемый файл wdtt-server не найден в текущей папке установки!${NC}"
  exit 1
fi

# Проверка наличия шаблонов и необходимых файлов
REQUIRED_FILES=("app.py" "99-wdtt.conf" "wdtt-panel.service.template" "wdtt-vpn.service.template")
for file in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "./$file" ]; then
    echo -e "${RED}Ошибка: Файл $file не найден в текущей папке установки!${NC}"
    exit 1
  fi
done

# --- ИНИЦИАЛИЗАЦИЯ ПЕРЕМЕННЫХ ОКРУЖЕНИЯ ---
init_vars() {
  if [ "$1" == "--local" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
    LOCAL_MODE=true
    echo -e "${YELLOW}--- Запущено в локальном режиме (LAN) ---${NC}"
  else
    SERVER_IP=$(curl -s https://icanhazip.com || echo "your-server-ip")
    LOCAL_MODE=false
    echo -e "${YELLOW}--- Запущено в стандартном режиме (VPS) ---${NC}"
  fi
}

# --- ПРОВЕРКА СВОБОДНЫХ ПОРТОВ ---
is_port_busy() {
  local port=$1
  if ss -tulpn 2>/dev/null | awk '{print $5}' | grep -qE ":$port$"; then
    return 0 # Порт занят
  else
    return 1 # Порт свободен
  fi
}

# Функция безопасного ввода порта с проверкой занятости
get_free_port() {
  local var_name=$1
  local default_val=$2
  local prompt_msg=$3
  local user_val

  while true; do
    read -p "$prompt_msg [default: $default_val]: " user_val
    user_val=${user_val:-$default_val}
    
    if is_port_busy "$user_val"; then
      echo -e "${RED}Внимание: Порт $user_val уже используется другим процессом в системе!${NC}"
      read -p "Вы уверены, что хотите использовать именно его? (y/N): " CONFIRM_PORT
      if [[ "$CONFIRM_PORT" =~ ^[Yy]$ ]]; then
        break
      fi
    else
      break
    fi
  done
  eval "$var_name=\$user_val"
}

# --- ФУНКЦИИ РЕЗЕРВНОГО КОПИРОВАНИЯ ---
backup_data() {
  if [ -d "/etc/wdtt" ]; then
    echo -e "${YELLOW}Создание резервной копии данных (/etc/wdtt)...${NC}"
    mkdir -p /tmp/wdtt_backup
    cp -rp /etc/wdtt/* /tmp/wdtt_backup/
    echo -e "${GREEN}Резервная копия успешно создана в /tmp/wdtt_backup/${NC}"
  else
    echo -e "${YELLOW}Папка /etc/wdtt не найдена. Создание бэкапа пропущено.${NC}"
  fi
}

restore_data() {
  if [ -d "/tmp/wdtt_backup" ] && [ "$(ls -A /tmp/wdtt_backup)" ]; then
    echo -e "${YELLOW}Восстановление данных из резервной копии...${NC}"
    mkdir -p /etc/wdtt
    cp -rp /tmp/wdtt_backup/* /etc/wdtt/
    chown -R root:root /etc/wdtt
    echo -e "${GREEN}Данные успешно восстановлены!${NC}"
    rm -rf /tmp/wdtt_backup
  fi
}

# --- ПОЛНОЕ УДАЛЕНИЕ СЛУЖБ (ДЛЯ ЧИСТОЙ УСТАНОВКИ) ---
clean_old_installation() {
  echo -e "${YELLOW}Удаление предыдущей установки...${NC}"
  systemctl stop wdtt-panel wdtt-vpn 2>/dev/null || true
  systemctl disable wdtt-panel wdtt-vpn 2>/dev/null || true
  rm -f /etc/systemd/system/wdtt-panel.service
  rm -f /etc/systemd/system/wdtt-vpn.service
  systemctl daemon-reload

  rm -rf /etc/wdtt
  rm -rf /opt/wdtt-panel
  rm -f /usr/local/bin/wdtt-server
  echo -e "${GREEN}Предыдущая установка полностью удалена.${NC}"
}

# --- ПРОСМОТР СТАТУСА СЕРВИСОВ ---
check_status() {
  echo -e "\n=== Статус сервисов WDTT ==="
  if systemctl is-active --quiet wdtt-panel; then
    echo -e "Панель управления (wdtt-panel): ${GREEN}Активна (Running)${NC}"
  else
    echo -e "Панель управления (wdtt-panel): ${RED}Не активна / Не установлена${NC}"
  fi

  if systemctl is-active --quiet wdtt-vpn; then
    echo -e "VPN Ядро (wdtt-vpn):            ${GREEN}Активно (Running)${NC}"
  else
    echo -e "VPN Ядро (wdtt-vpn):            ${RED}Не активно / Не установлено${NC}"
  fi
  echo -e "\n--- Детальный вывод systemctl ---"
  systemctl status wdtt-panel --no-pager -n 5 || true
  systemctl status wdtt-vpn --no-pager -n 5 || true
  echo ""
  read -p "Нажмите Enter для возврата в меню..."
}

# --- ОСНОВНАЯ ПРОЦЕДУРА УСТАНОВКИ ---
perform_installation() {
  local preserve_data=$1
  local alongside_wg=$2
  local SAFE_MODE=false

  if [ "$preserve_data" = true ]; then
    backup_data
  fi

  # Остановка старых служб перед копированием файлов
  systemctl stop wdtt-panel wdtt-vpn 2>/dev/null || true

  # Специфика выбора Безопасного режима при установке рядом с WireGuard
  if [ "$alongside_wg" = true ]; then
    echo -e "\n${BLUE}=== Настройка совместимости с WireGuard ===${NC}"
    echo -e "Безопасный режим предотвращает затирание текущих правил вашего файрвола (UFW/Firewalld)"
    echo -e "и не устанавливает пакет автосохранения правил (iptables-persistent)."
    read -p "Включить безопасный режим установки? (Y/n): " opt_safe
    opt_safe=${opt_safe:-Y}
    if [[ "$opt_safe" =~ ^[Yy]$ ]]; then
      SAFE_MODE=true
      echo -e "${GREEN}Безопасный режим активирован!${NC}"
    else
      SAFE_MODE=false
      echo -e "${YELLOW}Безопасный режим отключен. Установка продолжится в обычном режиме.${NC}"
    fi
  fi

  echo -e "\n=== Настройка параметров установки ==="

  # Сбор данных для Веб-панели (с попыткой восстановить старые значения)
  local default_user="admin"
  local default_pass=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)
  local default_panel_port="8080"
  local default_dtls_port="56000"
  local default_wg_port="56001"
  local default_tun_port="9000"

  if [ "$preserve_data" = true ] && [ -f /etc/systemd/system/wdtt-panel.service ]; then
    local ext_user=$(grep -oP '(PANEL_USER=|--user\s+)\K\S+' /etc/systemd/system/wdtt-panel.service | tr -d '"' | head -n1)
    local ext_pass=$(grep -oP '(PANEL_PASS=|--pass\s+)\K\S+' /etc/systemd/system/wdtt-panel.service | tr -d '"' | head -n1)
    local ext_port=$(grep -oP '(PANEL_PORT=|--port\s+)\K\S+' /etc/systemd/system/wdtt-panel.service | tr -d '"' | head -n1)
    
    [ -n "$ext_user" ] && default_user="$ext_user"
    [ -n "$ext_pass" ] && default_pass="$ext_pass"
    [ -n "$ext_port" ] && default_panel_port="$ext_port"
  fi

  read -p "Логин администратора веб-панели [default: $default_user]: " PANEL_USER
  PANEL_USER=${PANEL_USER:-$default_user}

  read -p "Пароль веб-панели [default: $default_pass]: " PANEL_PASS
  PANEL_PASS=${PANEL_PASS:-$default_pass}

  # Интерактивный опрос портов с автоматической проверкой на занятость в системе
  get_free_port PANEL_PORT "$default_panel_port" "Порт веб-панели"
  get_free_port DTLS_PORT "$default_dtls_port" "UDP-порт для DTLS"
  get_free_port WG_PORT "$default_wg_port" "Внутренний порт WireGuard"
  get_free_port TUN_PORT "$default_tun_port" "Локальный порт клиента (TUN)"

  # 1. Установка зависимостей
  echo -e "\n[1/6] Установка пакетов системы..."
  apt-get update
  export DEBIAN_FRONTEND=noninteractive
  
  local pkgs="python3 python3-pip python3-venv iptables curl jq"
  if [ "$SAFE_MODE" = false ]; then
    pkgs="$pkgs iptables-persistent"
  fi
  apt-get install -y $pkgs

  # 2. Копирование готового бинарника
  echo -e "\n[2/6] Копирование исполняемого файла ядра..."
  cp ./wdtt-server /usr/local/bin/wdtt-server
  chmod +x /usr/local/bin/wdtt-server

  # 3. Настройка служебных папок и базы данных
  echo -e "\n[3/6] Настройка служебных папок и базы данных..."
  mkdir -p /etc/wdtt
  mkdir -p /opt/wdtt-panel

  if [ "$preserve_data" = true ]; then
    restore_data
  fi

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
  else
    echo -e "${GREEN}Существующая база данных пользователей (/etc/wdtt/passwords.json) сохранена.${NC}"
  fi

  # 4. Конфигурация ядра и NAT сети
  echo -e "\n[4/6] Настройка sysctl и NAT..."
  cp 99-wdtt.conf /etc/sysctl.d/99-wdtt.conf
  sysctl -p /etc/sysctl.d/99-wdtt.conf

  MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
  if [ -n "$MAIN_IFACE" ]; then
    # Добавляем правило MASQUERADE
    if ! iptables -t nat -C POSTROUTING -o "$MAIN_IFACE" -j MASQUERADE 2>/dev/null; then
      iptables -t nat -A POSTROUTING -o "$MAIN_IFACE" -j MASQUERADE
    fi
    
    # В безопасном режиме пропускаем автосохранение правил файрвола на диск
    if [ "$SAFE_MODE" = false ]; then
      netfilter-persistent save
    fi
  fi

  # 5. Настройка веб-панели управления
  echo -e "\n[5/6] Создание окружения Python..."
  cp app.py /opt/wdtt-panel/app.py
  sed -i "s/56000,56001,9000/${DTLS_PORT},${WG_PORT},${TUN_PORT}/g" /opt/wdtt-panel/app.py

  python3 -m venv /opt/wdtt-panel/venv
  /opt/wdtt-panel/venv/bin/pip install --upgrade pip
  /opt/wdtt-panel/venv/bin/pip install flask werkzeug

  # 6. Настройка системных служб systemd из шаблонов
  echo -e "\n[6/6] Установка служб Systemd..."
  sed "s/{{PANEL_USER}}/${PANEL_USER}/g; s/{{PANEL_PASS}}/${PANEL_PASS}/g; s/{{PANEL_PORT}}/${PANEL_PORT}/g" wdtt-panel.service.template > /etc/systemd/system/wdtt-panel.service
  sed "s/{{DTLS_PORT}}/${DTLS_PORT}/g; s/{{WG_PORT}}/${WG_PORT}/g" wdtt-vpn.service.template > /etc/systemd/system/wdtt-vpn.service

  systemctl daemon-reload
  systemctl enable --now wdtt-panel
  systemctl enable --now wdtt-vpn

  echo -e "\n=================================================="
  echo -e "${GREEN}Установка успешно завершена!${NC}"
  echo -e "Панель управления доступна по адресу:"
  echo -e "http://$SERVER_IP:$PANEL_PORT"
  echo -e "Учетные данные: $PANEL_USER / $PANEL_PASS"
  
  if [ "$SAFE_MODE" = true ]; then
    echo -e "\n${YELLOW}ВНИМАНИЕ (Безопасный режим):${NC}"
    echo -e "Для сохранения работоспособности VPN после перезагрузки сервера"
    echo -e "добавьте следующее правило в ваш брандмауэр вручную (например, в UFW или Firewalld):"
    echo -e "${GREEN}iptables -t nat -A POSTROUTING -o $MAIN_IFACE -j MASQUERADE${NC}"
  fi
  echo -e "=================================================="
  read -p "Нажмите Enter для выхода..."
}

# --- МЕНЮ УСТАНОВКИ ---
show_menu() {
  clear
  echo -e "${BLUE}==================================================${NC}"
  echo -e "${BLUE}            Управление установкой WDTT VPN         ${NC}"
  echo -e "${BLUE}==================================================${NC}"
  echo -e "1) Обычная установка"
  echo -e "2) Установить рядом с обычным WireGuard (с безопасным режимом)"
  echo -e "3) Переустановить без потери пользователей, ключей и хэшей"
  echo -e "4) Полностью переустановить (чистая установка)"
  echo -e "5) Посмотреть статус сервисов"
  echo -e "6) Выход"
  echo -e "${BLUE}==================================================${NC}"
  read -p "Выберите пункт меню [1-6]: " MENU_CHOICE
}

# --- ТОЧКА ВХОДА ---
init_vars "$1"

while true; do
  show_menu
  case $MENU_CHOICE in
    1)
      echo -e "\n--- Запуск обычной установки ---"
      perform_installation false false
      break
      ;;
    2)
      echo -e "\n--- Запуск установки рядом с WireGuard ---"
      perform_installation false true
      break
      ;;
    3)
      echo -e "\n--- Запуск обновления без потери данных ---"
      perform_installation true false
      break
      ;;
    4)
      echo -e "\n${RED}ВНИМАНИЕ: Это действие полностью сотрет базу данных пользователей и конфигурации!${NC}"
      read -p "Вы уверены, что хотите продолжить? (y/N): " CONFIRM
      if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        clean_old_installation
        perform_installation false false
      else
        echo "Операция отменена."
        sleep 1.5
      fi
      break
      ;;
    5)
      check_status
      ;;
    6)
      echo "Выход из установщика."
      exit 0
      ;;
    *)
      echo -e "${RED}Неверный выбор. Пожалуйста, введите цифру от 1 до 6.${NC}"
      sleep 1.5
      ;;
  esac
done
