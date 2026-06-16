import os
import json
import random
import string
import urllib.request
from functools import wraps
from flask import Flask, request, render_template_string, Response, redirect

app = Flask(__name__)

DB_PATH = '/etc/wdtt/passwords.json'
ADMIN_USER = os.environ.get('PANEL_USER', 'admin')
ADMIN_PASS = os.environ.get('PANEL_PASS', 'admin')

def check_auth(username, password):
    return username == ADMIN_USER and password == ADMIN_PASS

def authenticate():
    return Response(
        'Требуется авторизация.',
        401,
        {'WWW-Authenticate': 'Basic realm="Login Required"'}
    )

def requires_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.authorization
        if not auth or not check_auth(auth.username, auth.password):
            return authenticate()
        return f(*args, **kwargs)
    return decorated

def load_db():
    default_db = {
        "main_password": "".join(random.choices(string.ascii_letters + string.digits, k=16)),
        "admin_id": "",
        "bot_token": "",
        "passwords": {},
        "devices": {}
    }
    if not os.path.exists(DB_PATH):
        return default_db
    try:
        with open(DB_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
            if "passwords" not in data or not isinstance(data["passwords"], dict):
                raise ValueError("Old format")
            return data
    except Exception:
        return default_db

def save_db(data):
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    with open(DB_PATH, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=4, ensure_ascii=False)
    # Перезапускаем VPN-сервер для применения изменений
    os.system("systemctl restart wdtt-vpn >/dev/null 2>&1")

def get_public_ip():
    try:
        return urllib.request.urlopen('https://icanhazip.com', timeout=3).read().decode('utf-8').strip()
    except Exception:
        return "127.0.0.1"

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="ru" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WDTT VPN | Панель Управления</title>
    <!-- Стандартный Bootstrap 5 -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <!-- Стандартный пакет иконок -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css" rel="stylesheet">
</head>
<body class="bg-dark text-light">
<div class="container my-5">
    
    <!-- Шапка панели -->
    <div class="d-flex justify-content-between align-items-center mb-4 pb-3 border-bottom border-secondary">
        <h3><i class="bi bi-shield-lock-fill text-primary me-2"></i>WDTT VPN Manager</h3>
        <span class="badge bg-secondary">wdtt0</span>
    </div>

    <!-- Добавить пользователя -->
    <div class="card mb-4 border-secondary">
        <div class="card-header bg-body-tertiary border-secondary">
            <i class="bi bi-plus-circle me-2"></i>Добавить пользователя
        </div>
        <div class="card-body">
            <form action="/add" method="POST" class="row g-3">
                <div class="col-md-3">
                    <input type="text" class="form-control" name="name" placeholder="Имя (напр. iPhone)" required>
                </div>
                <div class="col-md-7">
                    <input type="text" class="form-control" name="vk_hash" placeholder="VK Звонок (Хеш или ссылка)" required>
                </div>
                <div class="col-md-2">
                    <button type="submit" class="btn btn-primary w-100">Создать</button>
                </div>
            </form>
        </div>
    </div>

    <!-- Список активных ключей -->
    <div class="card border-secondary">
        <div class="card-header bg-body-tertiary border-secondary">
            <i class="bi bi-people-fill me-2"></i>Активные ключи
        </div>
        <div class="card-body p-0">
            <div class="table-responsive">
                <table class="table table-hover align-middle text-center mb-0">
                    <thead>
                        <tr>
                            <th>Имя</th>
                            <th>Порты (DTLS,WG,TUN)</th>
                            <th>VK Hash</th>
                            <th>Пароль (Ключ)</th>
                            <th>Ссылка для подключения</th>
                            <th>Действие</th>
                        </tr>
                    </thead>
                    <tbody>
                        {% for pass_val, u in db.passwords.items() %}
                        <tr>
                            <td class="fw-bold text-white">{{ u.name or "Без имени" }}</td>
                            <td><span class="badge bg-secondary">{{ u.ports or "56000,56001,9000" }}</span></td>
                            <td><small class="text-muted">{{ u.vk_hash }}</small></td>
                            <td><code>{{ pass_val }}</code></td>
                            <td style="width: 320px;">
                                <div class="input-group">
                                    <input type="text" class="form-control form-control-sm text-center" 
                                           id="link-{{ loop.index }}" 
                                           value="wdtt://{{ server_ip }}:{{ u.ports.split(',')[0] }}:{{ u.ports.split(',')[1] }}:{{ u.ports.split(',')[2] }}:{{ pass_val }}:{{ u.vk_hash }}" 
                                           readonly>
                                    <button class="btn btn-outline-secondary btn-sm" type="button" onclick="copyLink('link-{{ loop.index }}', this)">
                                        <i class="bi bi-copy"></i>
                                    </button>
                                </div>
                            </td>
                            <td>
                                <form action="/delete/{{ pass_val }}" method="POST" onsubmit="return confirm('Удалить?');" class="m-0">
                                    <button type="submit" class="btn btn-sm btn-danger">Удалить</button>
                                </form>
                            </td>
                        </tr>
                        {% endfor %}
                        {% if not db.passwords %}
                        <tr>
                            <td colspan="6" class="text-muted py-4">Нет активных пользователей. Создайте первого!</td>
                        </tr>
                        {% endif %}
                    </tbody>
                </table>
            </div>
        </div>
    </div>
</div>

<script>
function copyLink(inputId, btn) {
    const input = document.getElementById(inputId);
    input.select();
    navigator.clipboard.writeText(input.value);
    
    // Простая индикация успеха иконкой
    btn.innerHTML = '<i class="bi bi-check-lg text-success"></i>';
    setTimeout(() => {
        btn.innerHTML = '<i class="bi bi-copy"></i>';
    }, 1200);
}
</script>
</body>
</html>
"""

@app.route('/')
@requires_auth
def index():
    db = load_db()
    server_ip = get_public_ip()
    return render_template_string(HTML_TEMPLATE, db=db, server_ip=server_ip)

@app.route('/add', methods=['POST'])
@requires_auth
def add_user():
    db = load_db()
    
    vk_input = request.form.get('vk_hash', '').strip()
    vk_hash = vk_input
    if 'join/' in vk_input:
        vk_hash = vk_input.split('join/')[-1].split('?')[0].split('/')[0]
    
    passChars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789"
    password = "".join(random.choices(passChars, k=16))
    ports = "56000,56001,9000"
    
    db["passwords"][password] = {
        "name": request.form.get('name', 'User'),
        "device_id": "",
        "expires_at": 0,
        "down_bytes": 0,
        "up_bytes": 0,
        "vk_hash": vk_hash,
        "ports": ports,
        "is_deactivated": False
    }
    
    save_db(db)
    return redirect('/')

@app.route('/delete/<password_val>', methods=['POST'])
@requires_auth
def delete_user(password_val):
    db = load_db()
    if password_val in db["passwords"]:
        del db["passwords"][password_val]
    save_db(db)
    return redirect('/')

if __name__ == '__main__':
    port = int(os.environ.get('PANEL_PORT', 8080))
    app.run(host='0.0.0.0', port=port)
