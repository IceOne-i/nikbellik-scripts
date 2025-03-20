#!/bin/bash
set -e  # Остановка при ошибке

# 1. Проверяем, переданы ли аргументы
if [ $# -ne 3 ] && [ "$1" != "remove" ]; then
    echo "❌ Ошибка: Неверное количество аргументов!"
    echo "Использование для установки: $0 <default_voice_port> <filetransfer_port> <query_port>"
    echo "Использование для удаления: $0 remove"
    exit 1
fi

VOICE_PORT=$1
FILETRANSFER_PORT=$2
QUERY_PORT=$3
TOKEN="Не найден"

log() {
    echo "➡ $1"
}

install_package() {
    if dpkg -s "$1" &> /dev/null; then
        log "$1 уже установлен, пропускаем..."
    else
        log "Установка $1..."
        apt-get install -y -qq "$1" >/dev/null 2>&1
    fi
}

remove_teamspeak() {
    log "Удаление TeamSpeak..."
    systemctl stop teamspeak >/dev/null 2>&1 || true
    systemctl disable teamspeak >/dev/null 2>&1 || true
    userdel -r teamspeak >/dev/null 2>&1 || true
    rm -rf /opt/teamspeak
    rm -f /etc/systemd/system/teamspeak.service
    systemctl daemon-reload >/dev/null 2>&1
    log "✅ TeamSpeak успешно удален!"
}

install_teamspeak() {
    log "Обновление списка пакетов..."
    apt-get update -qq >/dev/null 2>&1

    log "Полное обновление системы..."
    apt-get full-upgrade -y -qq >/dev/null 2>&1  # Флаг -y для автоматического подтверждения

    install_package qemu-guest-agent
    install_package bzip2

    log "Создание пользователя teamspeak..."
    useradd -mrd /opt/teamspeak teamspeak -s "$(which bash)" >/dev/null 2>&1 || true

    log "Скачивание и установка TeamSpeak..."
    su - teamspeak -c "
        wget -q https://files.teamspeak-services.com/releases/server/3.13.7/teamspeak3-server_linux_amd64-3.13.7.tar.bz2 -O /opt/teamspeak/teamspeak-server.tar.bz2 &&
        tar xvfj /opt/teamspeak/teamspeak-server.tar.bz2 -C /opt/teamspeak --strip-components 1 &&
        touch /opt/teamspeak/.ts3server_license_accepted
    " >/dev/null 2>&1

    log "Создание systemd-сервиса для TeamSpeak..."
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

    log "Перезагрузка systemd и запуск TeamSpeak..."
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable --now teamspeak >/dev/null 2>&1

    log "Ожидание генерации логов (2 секунды)..."
    sleep 2

    log "Поиск токена администратора..."
    if ls /opt/teamspeak/logs/ >/dev/null 2>&1; then
        TOKEN=$(grep -i "token=" /opt/teamspeak/logs/* | sed -E 's/.*token=//')
        TOKEN=${TOKEN:-"Не найден"}  # Если переменная пустая, записать "Не найден"
    else
        TOKEN="Не найден (папка логов отсутствует)"
    fi

    log "✅ Установка завершена!"

    # Итоговое сообщение
    echo "------------------------------------------------------------"
    echo "✅ TeamSpeak успешно установлен!"
    echo "🔹 Голосовой порт: $VOICE_PORT"
    echo "🔹 Порт передачи файлов: $FILETRANSFER_PORT"
    echo "🔹 Порт для запросов: $QUERY_PORT"
    echo "🔹 Статус сервиса: $(systemctl is-active teamspeak)"
    echo "🔹 Токен администратора: $TOKEN"
    echo "------------------------------------------------------------"

    # Вопрос о выключении машины
    while true; do
        printf "\033[32;1m🔴 Хотите выключить сервер? (y/n)\033[0m\n"
        read -r -p '' shutdown_choice
        case "$shutdown_choice" in
            y|Y )
                log "Выключение системы..."
                shutdown -h now
                break
                ;;
            n|N )
                log "Сервер остается включенным."
                break
                ;;
            * )
                echo "❌ Пожалуйста, введите y или n"
                ;;
        esac
    done
}

# Проверка, установлен ли TeamSpeak
if [ -d "/opt/teamspeak" ]; then
    printf "\033[33;1m⚠ TeamSpeak уже установлен!\033[0m\n"
    printf "\033[32;1mХотите удалить его? (y/n)\033[0m\n"

    while true; do
        read -r -p '' choice
        case "$choice" in
            y|Y )
                remove_teamspeak
                exit 0
                ;;
            n|N )
                echo "🚪 Выход из установки."
                exit 0
                ;;
            * )
                echo "❌ Пожалуйста, введите y или n"
                ;;
        esac
    done
fi

# Если дошли до этого момента, значит TeamSpeak не установлен
install_teamspeak
