#!/bin/bash
set -euo pipefail

#####################################
# install_teamspeak.sh
# Устанавливает или удаляет TeamSpeak 3 Server
# Запуск: sh <(wget -qO- URL/common_utils.sh) -- <XXX|remove>
#####################################

# Подключаем утилиты из common_utils.sh
source <(wget -qO- https://raw.githubusercontent.com/IceOne-i/nikbellik-scripts/refs/heads/main/common_utils.sh)

# ------------------------------
# Удаление TeamSpeak
# ------------------------------
remove_teamspeak() {
    log "Удаление TeamSpeak..."
    systemctl stop teamspeak    >/dev/null 2>&1 || true
    systemctl disable teamspeak >/dev/null 2>&1 || true
    userdel -r teamspeak        >/dev/null 2>&1 || true
    rm -rf /opt/teamspeak
    rm -f /etc/systemd/system/teamspeak.service
    systemctl daemon-reload     >/dev/null 2>&1

    remove_auto_update
    log "✅ TeamSpeak успешно удален!"
}

# ------------------------------
# Установка TeamSpeak
# ------------------------------
install_teamspeak() {
    update_and_upgrade_system

    install_package qemu-guest-agent
    install_package bzip2

    log "Создание пользователя teamspeak..."
    useradd -mrd /opt/teamspeak teamspeak -s "$(which bash)" >/dev/null 2>&1 || true

    # Порты
    VOICE_PORT="${PREFIX}7"
    FILETRANSFER_PORT="${PREFIX}1"
    QUERY_PORT="${PREFIX}2"

    log "Скачивание и распаковка TeamSpeak..."
    su - teamspeak -c "
      wget -q https://files.teamspeak-services.com/releases/server/3.13.7/teamspeak3-server_linux_amd64-3.13.7.tar.bz2 \
        -O /opt/teamspeak/teamspeak-server.tar.bz2 &&
      tar xvjf /opt/teamspeak/teamspeak-server.tar.bz2 -C /opt/teamspeak --strip-components 1 &&
      touch /opt/teamspeak/.ts3server_license_accepted
    " >/dev/null 2>&1

    log "Создание systemd-сервиса для TeamSpeak..."
    cat <<EOF > /etc/systemd/system/teamspeak.service
[Unit]
Description=TeamSpeak 3 Server
Wants=network.target

[Service]
WorkingDirectory=/opt/teamspeak
User=teamspeak
ExecStart=/opt/teamspeak/ts3server_minimal_runscript.sh \
    default_voice_port=$VOICE_PORT voice_ip=0.0.0.0 \
    filetransfer_port=$FILETRANSFER_PORT filetransfer_ip=0.0.0.0 \
    query_port=$QUERY_PORT query_ip=0.0.0.0
ExecStop=/opt/teamspeak/ts3server_startscript.sh stop
ExecReload=/opt/teamspeak/ts3server_startscript.sh restart
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF

    log "Перезапуск systemd и запуск TeamSpeak..."
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable --now teamspeak >/dev/null 2>&1

    # Ждём генерации логов
    sleep 2

    # Извлекаем полный токен (включая + и любые символы до конца строки)
    TOKEN=$(grep -i "token=" /opt/teamspeak/logs/* \
             | head -n1 \
             | sed -E 's/.*token=//')

    log "✅ Установка TeamSpeak завершена!"
    cat <<EOF
------------------------------------------------------------
✅ TeamSpeak успешно установлен!
🔹 Голосовой порт: $VOICE_PORT
🔹 Порт передачи файлов: $FILETRANSFER_PORT
🔹 Порт запросов: $QUERY_PORT
🔹 Статус сервиса: $(systemctl is-active teamspeak)
🔹 Токен администратора: $TOKEN
------------------------------------------------------------
EOF

    setup_auto_update
    confirm_shutdown
}

# ------------------------------
# Обработка аргументов
# ------------------------------
if [ "${1:-}" = "--" ]; then shift; fi
case "${1:-}" in
    remove)
        remove_teamspeak
        exit 0
        ;;
    [0-9][0-9][0-9])
        PREFIX="$1"
        ;;
    *)
        echo "❌ Ошибка: требуется аргумент <XXX> или remove"
        exit 1
        ;;
esac

# Проверка существования
if [ -d "/opt/teamspeak" ]; then
    log "⚠ TeamSpeak уже установлен!"
    read -p "Хотите удалить его? (y/n): " yn
    case "$yn" in
        [Yy]*) remove_teamspeak; exit 0 ;;
        *)     exit 0 ;;
    esac
fi

# Запуск установки
install_teamspeak
