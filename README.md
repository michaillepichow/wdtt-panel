# WDTT VPN Manager

Легковесный VPN-сервер **WDTT** и веб-панель на Flask для удобного управления пользователями и ключами.

## О проекте
* **Панель:** Создание/удаление клиентов, копирование ссылок `wdtt://` через веб-интерфейс.
* **Туннелирование:** Готовый бинарный файл `wdtt-server` (маскировка под VK-звонки для обхода белых списков).
* **Службы:** Работает в фоновом режиме через Systemd. Сетевые настройки (NAT/Forwarding) применяются автоматически.

## Совместимые клиенты
Для подключения к созданному серверу используйте следующие приложения:
* **Android (Мобильный клиент):** [proxy-turn-vk-android](https://github.com/amurcanov/proxy-turn-vk-android)
* **Windows / Linux (ПК клиент):** [PWDTT](https://github.com/luminescq/PWDTT)
<img width="1000" height="738" alt="MyCollages (1)" src="https://github.com/user-attachments/assets/549c6624-978c-4b00-aae2-d195e470a1d1" />

## Быстрая установка (Ubuntu 20.04+)

Выполните на чистом сервере под root:

```bash
git clone https://github.com/michaillepichow/wdtt-panel.git
cd wdtt-panel
chmod +x install.sh
sudo ./install.sh
```




```
бинарник wdtt-server скомпилирован из официальных исходников wdtt
```

Если вам необходимо перезапустить, остановить или запустить компоненты сервера вручную:

*   **Перезапустить всё после изменений:**
    ```bash
    sudo systemctl restart wdtt-panel wdtt-vpn
    ```
*   **Остановить службы:**
    ```bash
    sudo systemctl stop wdtt-panel wdtt-vpn
    ```
*   **Проверить статус работы (активны ли процессы):**
    ```bash
    systemctl status wdtt-panel
    systemctl status wdtt-vpn
    ```

### 2. Просмотр логов в реальном времени

Логи помогают понять, кто подключается к серверу, происходят ли ошибки авторизации или сетевые сбои:

*   **Логи веб-панели (запросы, авторизация, добавление ключей):**
    ```bash
    journalctl -u wdtt-panel -f
    ```
*   **Логи VPN-сервера (подключения клиентов, трафик, работа DTLS):**
    ```bash
    journalctl -u wdtt-vpn -f
    ```

### 3. Сетевая диагностика

Проверка того, правильно ли сервер принимает трафик и работают ли порты:

*   **Проверить, запущены ли порты веб-панели и туннелей:**
    ```bash
    ss -tulpn | grep -E "wdtt|python"
    ```
    *(Вы должны увидеть порты панели, DTLS и WireGuard в режиме прослушивания).*

*   **Проверить, активно ли правило NAT (маскарадинг трафика):**
    ```bash
    sudo iptables -t nat -L POSTROUTING -n -v
    ```
    *(В выводе должно присутствовать правило с действием `MASQUERADE`).*

*   **Посмотреть статус сетевого форвардинга (пересылки пакетов):**
    ```bash
    sysctl net.ipv4.ip_forward
    ```
    *(Должно быть равно `net.ipv4.ip_forward = 1`).*
