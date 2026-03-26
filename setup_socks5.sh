#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

CONFIG_FILE="/etc/danted.conf"

echo -e "${CYAN}"
echo "============================================"
echo "   SOCKS5 прокси — Telegram + Браузер"
echo "============================================"
echo -e "${NC}"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] Запустите от root: sudo bash setup_socks5.sh${NC}"
    exit 1
fi

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo -e "${RED}[!] Не найдена команда: $1${NC}"
        exit 1
    }
}

detect_interface() {
    local iface
    iface="$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    if [[ -z "$iface" ]]; then
        iface="$(ip route | awk '/default/ {print $5; exit}')"
    fi
    echo "$iface"
}

detect_server_ip() {
    local ip=""
    ip="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
    if [[ -z "$ip" ]]; then
        ip="$(hostname -I | awk '{print $1}')"
    fi
    echo "$ip"
}

generate_password() {
    openssl rand -base64 24 | tr -d '=+/' | cut -c1-20
}

ask_password_twice() {
    local p1="" p2=""
    while true; do
        read -r -s -p "$(echo -e ${YELLOW})[?] Пароль: $(echo -e ${NC})" p1
        echo ""
        read -r -s -p "$(echo -e ${YELLOW})[?] Повторите пароль: $(echo -e ${NC})" p2
        echo ""
        if [[ -n "$p1" && "$p1" == "$p2" ]]; then
            PASSWORD="$p1"
            return 0
        fi
        echo -e "${RED}[!] Пароли не совпадают или пустые, попробуйте снова${NC}"
    done
}

ensure_base_cmds() {
    need_cmd ip
    need_cmd curl
}

ensure_install_deps() {
    echo -e "${CYAN}[*] Устанавливаю зависимости...${NC}"
    apt-get update -qq
    apt-get install -y dante-server qrencode curl openssl >/dev/null 2>&1
    echo -e "${GREEN}[✓] Зависимости установлены${NC}"
}

ensure_quick_cmds_for_user_add() {
    if ! command -v qrencode >/dev/null 2>&1; then
        echo -e "${YELLOW}[~] qrencode не найден, ставлю только его...${NC}"
        apt-get update -qq
        apt-get install -y qrencode >/dev/null 2>&1
    fi

    if ! command -v openssl >/dev/null 2>&1; then
        echo -e "${YELLOW}[~] openssl не найден, ставлю только его...${NC}"
        apt-get update -qq
        apt-get install -y openssl >/dev/null 2>&1
    fi
}

write_config() {
    local iface="$1"
    local port="$2"

    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

    cat > "$CONFIG_FILE" <<EOF
logoutput: syslog

internal: 0.0.0.0 port = ${port}
external: ${iface}

user.privileged: root
user.unprivileged: nobody

clientmethod: none
socksmethod: username

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

client block {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: connect
    socksmethod: username
    log: connect disconnect error
}

socks block {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
}
EOF
}

validate_config() {
    if ! /usr/sbin/danted -D -f "$CONFIG_FILE" >/tmp/danted_check.log 2>&1; then
        echo -e "${RED}[!] Конфиг Dante не прошёл проверку${NC}"
        cat /tmp/danted_check.log
        exit 1
    fi
}

restart_dante() {
    systemctl enable danted >/dev/null 2>&1
    systemctl restart danted
    if ! systemctl is-active --quiet danted; then
        echo -e "${RED}[!] Dante не запустился${NC}"
        journalctl -u danted -n 30 --no-pager
        exit 1
    fi
    echo -e "${GREEN}[✓] Dante запущен${NC}"
}

open_firewall() {
    local port="$1"
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${port}/tcp" >/dev/null 2>&1 || true
        echo -e "${GREEN}[✓] Порт ${port} открыт в UFW${NC}"
    fi
}

create_or_update_user() {
    local user="$1"
    local pass="$2"

    if id "$user" >/dev/null 2>&1; then
        echo -e "${YELLOW}[~] Пользователь ${user} уже существует, обновляю пароль${NC}"
    else
        useradd -r -s /usr/sbin/nologin "$user"
        echo -e "${GREEN}[✓] Пользователь ${user} создан${NC}"
    fi

    echo "${user}:${pass}" | chpasswd
    echo -e "${GREEN}[✓] Пароль для ${user} установлен${NC}"
}

print_qr() {
    local text="$1"
    qrencode -t ANSIUTF8 "$text" || true
}

show_links() {
    local server_ip="$1"
    local port="$2"
    local user="$3"
    local pass="$4"

    local tg_link="https://t.me/socks?server=${server_ip}&port=${port}&user=${user}&pass=${pass}"
    local browser_uri="socks5://${user}:${pass}@${server_ip}:${port}"
    local export_file="/root/proxy_${user}.txt"

    cat > "$export_file" <<EOF
SOCKS5
Server: ${server_ip}
Port: ${port}
Username: ${user}
Password: ${pass}

Telegram:
Settings -> Data and Storage -> Proxy -> Add Proxy -> SOCKS5

Firefox:
HTTP proxy: пусто
HTTPS proxy: пусто
SOCKS Host: ${server_ip}
Port: ${port}
SOCKS v5: ON
Proxy DNS through SOCKS v5: ON
Не запрашивать аутентификацию: НЕ включать

URI:
${browser_uri}

Telegram link:
${tg_link}
EOF

    echo ""
    echo -e "${BLUE}📱 Telegram${NC}"
    echo -e "Ссылка:"
    echo -e "${CYAN}${tg_link}${NC}"
    echo ""
    echo -e "${BLUE}QR-код Telegram:${NC}"
    print_qr "$tg_link"

    echo ""
    echo -e "${MAGENTA}🌐 Браузер / URI${NC}"
    echo -e "URI:"
    echo -e "${CYAN}${browser_uri}${NC}"
    echo ""
    echo -e "${MAGENTA}QR-код URI:${NC}"
    print_qr "$browser_uri"

    echo ""
    echo -e "${YELLOW}Firefox настраивать вручную:${NC}"
    echo -e "  HTTP прокси: пусто"
    echo -e "  HTTPS прокси: пусто"
    echo -e "  Узел SOCKS: ${CYAN}${server_ip}${NC}"
    echo -e "  Порт:       ${CYAN}${port}${NC}"
    echo -e "  SOCKS v5:   ${CYAN}включить${NC}"
    echo -e "  DNS через SOCKS5: ${CYAN}включить${NC}"
    echo -e "  Не запрашивать аутентификацию: ${CYAN}не включать${NC}"

    echo ""
    echo -e "${GREEN}[✓] Данные также сохранены в ${export_file}${NC}"
}

get_current_port() {
    local port
    port="$(sed -n 's/^internal: .* port = \([0-9][0-9]*\)$/\1/p' "$CONFIG_FILE" | head -n1)"
    echo "${port:-443}"
}

install_proxy() {
    local interface server_ip port username
    interface="$(detect_interface)"
    server_ip="$(detect_server_ip)"

    echo -e "${GREEN}[✓] Интерфейс: ${interface}${NC}"
    echo -e "${GREEN}[✓] Внешний IP: ${server_ip}${NC}"
    echo ""

    read -r -p "$(echo -e ${YELLOW})[?] Порт прокси [по умолчанию 443]: $(echo -e ${NC})" port
    port="${port:-443}"

    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        echo -e "${RED}[!] Некорректный порт${NC}"
        exit 1
    fi

    read -r -p "$(echo -e ${YELLOW})[?] Логин пользователя [по умолчанию tguser]: $(echo -e ${NC})" username
    username="${username:-tguser}"

    if [[ -z "$username" ]]; then
        echo -e "${RED}[!] Пустой логин недопустим${NC}"
        exit 1
    fi

    if command -v openssl >/dev/null 2>&1; then
        read -r -p "$(echo -e ${YELLOW})[?] Сгенерировать пароль автоматически? (Y/n): $(echo -e ${NC})" genpass
        if [[ -z "${genpass:-}" || "$genpass" =~ ^[Yy]$ ]]; then
            PASSWORD="$(generate_password)"
            echo -e "${GREEN}[✓] Сгенерирован пароль: ${PASSWORD}${NC}"
        else
            ask_password_twice
        fi
    else
        ask_password_twice
    fi

    ensure_install_deps
    write_config "$interface" "$port"
    validate_config
    create_or_update_user "$username" "$PASSWORD"
    restart_dante
    open_firewall "$port"

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}   Прокси успешно запущен${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo -e "Тип:     ${CYAN}SOCKS5${NC}"
    echo -e "Сервер:  ${CYAN}${server_ip}${NC}"
    echo -e "Порт:    ${CYAN}${port}${NC}"
    echo -e "Логин:   ${CYAN}${username}${NC}"
    echo -e "Пароль:  ${CYAN}${PASSWORD}${NC}"

    show_links "$server_ip" "$port" "$username" "$PASSWORD"
}

add_new_user() {
    local username port server_ip
    server_ip="$(detect_server_ip)"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}[!] ${CONFIG_FILE} не найден. Сначала установите прокси.${NC}"
        exit 1
    fi

    ensure_base_cmds
    ensure_quick_cmds_for_user_add

    port="$(get_current_port)"

    read -r -p "$(echo -e ${YELLOW})[?] Логин нового пользователя: $(echo -e ${NC})" username
    if [[ -z "$username" ]]; then
        echo -e "${RED}[!] Логин не может быть пустым${NC}"
        exit 1
    fi

    read -r -p "$(echo -e ${YELLOW})[?] Сгенерировать пароль автоматически? (Y/n): $(echo -e ${NC})" genpass
    if [[ -z "${genpass:-}" || "$genpass" =~ ^[Yy]$ ]]; then
        PASSWORD="$(generate_password)"
        echo -e "${GREEN}[✓] Сгенерирован пароль: ${PASSWORD}${NC}"
    else
        ask_password_twice
    fi

    create_or_update_user "$username" "$PASSWORD"

    echo ""
    echo -e "${GREEN}[✓] Новый пользователь добавлен${NC}"
    echo -e "Сервер:  ${CYAN}${server_ip}${NC}"
    echo -e "Порт:    ${CYAN}${port}${NC}"
    echo -e "Логин:   ${CYAN}${username}${NC}"
    echo -e "Пароль:  ${CYAN}${PASSWORD}${NC}"

    show_links "$server_ip" "$port" "$username" "$PASSWORD"
}

ensure_base_cmds

echo -e "${YELLOW}Выберите действие:${NC}"
echo "1) Установить / переустановить прокси"
echo "2) Добавить нового пользователя"
read -r -p "Введите номер [1-2]: " MODE

case "$MODE" in
    1) install_proxy ;;
    2) add_new_user ;;
    *)
        echo -e "${RED}[!] Неверный выбор${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${CYAN}Проверка:${NC}"
echo "  systemctl status danted --no-pager"
echo "  journalctl -u danted -n 30 --no-pager"
echo "  ss -lntp | grep danted"