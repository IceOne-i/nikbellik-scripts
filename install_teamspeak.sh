#!/bin/bash
set -e

# Загрузка и исполнение утилитарного скрипта
source <(wget -qO- https://raw.githubusercontent.com/IceOne-i/nikbellik-scripts/main/common-utils.sh)

# ------------------------------
# Удаление TeamSpeak
# ------------------------------
remove_teamspeak() {
    log "Удаление TeamSpeak..."
    systemctl stop teamspeak >/dev/null 2>&1 || true
    systemctl disable teamspeak >/dev/null 2>&1 || true
    userdel -r teamspeak >/dev/null 2>&1 || true
    rm -rf /opt/teamspeak
    rm -f /etc/systemd/system/teamspeak.service
    systemctl daemon-reload >/dev/null 2>&1

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

    VOICE_PORT="${PREFIX}7"
    FILETRANSFER_PORT="${PREFIX}1"
    QUERY_PORT="${PREFIX}2"

    log "Скачивание и распаковка TeamSpeak..."
    su - teamspeak -c "
        wget -q https://files.teamspeak-services.com/releases/server/3.13.7/teamspeak3-server_linux_amd64-3.13.7.tar.bz2 -O /opt/teamspeak/teamspeak-server.tar.bz2 &&
        tar xvfj /opt/teamspeak/teamspeak-server.tar.bz2 -C /opt/teamspeak --strip-components 1 &&
        touch /opt/teamspeak/.ts3server_license_accepted
    " >/dev/null 2>&1

    log "Создание systemd‑сервиса..."
    cat <<EOT > /etc/systemd/system/teamspeak.service
[Unit]
Description=Teamspeak Service
Wants=network.target

[Service]
WorkingDirectory=/opt/teamspeak
User=teamspeak
ExecStart=/opt/teamspeak/ts3server_minimal_runscript.sh default_voice_port=$VOICE_PORT voice_ip=0.0.0.0 filetransfer_port=$FILETRANSFER_PORT filetransfer_ip=0.0.0.0 query_port=$QUERY_PORT query_ip=0.0.0.0
ExecStop=/opt/teamspeak/ts3server_startscript.sh stop
ExecReload=/opt/teamspeak/ts3server_startscript.sh restart
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
EOT

    log "Перезапуск systemd и старт TeamSpeak..."
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable --now teamspeak >/dev/null 2>&1

    sleep 2
    TOKEN=$(grep -i "token=" /opt/teamspeak/logs/* 2>/dev/null | sed -E 's/.*token=//' || echo "Не найден")

    echo "------------------------------------------------------------"
    echo "✅ TeamSpeak установлен!"
    echo "🔹 Голосовой порт: $VOICE_PORT"
    echo "🔹 Порт передачи файлов: $FILETRANSFER_PORT"
    echo "🔹 Query порт: $QUERY_PORT"
    echo "🔹 Статус: $(systemctl is-active teamspeak)"
    echo "🔹 Токен администратора: $TOKEN"
    echo "------------------------------------------------------------"

    setup_auto_update
    ask_for_shutdown
}

# ------------------------------
# Точка входа
# ------------------------------
if [ $# -ne 1 ] && [ "$1" != "remove" ]; then
    echo "❌ Ошибка: требуется один аргумент!"
    echo "Использование: $0 <XXX> (три цифры порта) или $0 remove"
    exit 1
fi

if [ "$1" == "remove" ]; then
    remove_teamspeak
    exit 0
fi

PREFIX=$1
if ! [[ $PREFIX =~ ^[0-9]{3}$ ]]; then
    echo "❌ Префикс должен быть из трёх цифр"
    exit 1
fi

if [ -d "/opt/teamspeak" ]; then
    echo -e "\033[33;1m⚠ TeamSpeak уже установлен!\033[0m"
    echo -e "\033[32;1mХотите удалить его? (y/n)\033[0m"
    while true; do
        read -r choice
        case "$choice" in
            y|Y ) remove_teamspeak; exit 0 ;;
            n|N ) echo "🚪 Выход."; exit 0 ;;
            * ) echo "❌ Введите y или n" ;;
        esac
    done
fi

install_teamspeak
