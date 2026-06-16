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
