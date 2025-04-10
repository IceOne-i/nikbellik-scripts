#!/bin/bash
set -e  # Остановка при ошибке

# 1. Проверяем, запущен ли скрипт от root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Скрипт должен быть запущен от имени root!"
    exit 1
fi

# 2. Проверяем аргументы
if [ $# -ne 1 ] && [ "$1" != "remove" ]; then
    echo "❌ Ошибка: требуется один аргумент!"
    echo "Использование для установки: $0 <XXX> (где XXX — первые три цифры порта)"
    echo "Использование для удаления: $0 remove"
    exit 1
fi

# Если аргумент — "remove", вызываем удаление
if [ "$1" == "remove" ]; then
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

    log() {
        echo "➡ $1"
    }

    remove_teamspeak
    exit 0
fi

# Генерация портов
PREFIX=$1
if ! [[ $PREFIX =~ ^[0-9]{3}$ ]]; then
    echo "❌ Ошибка: префикс должен состоять из трёх цифр"
    exit 1
fi

VOICE_PORT="${PREFIX}7"
FILETRANSFER_PORT="${PREFIX}1"
QUERY_PORT="${PREFIX}2"
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

install_teamspeak() {
    log "Обновление списка пакетов..."
    apt-get update -qq >/dev/null 2>&1

    PACKAGES=$(apt list --upgradable 2>/dev/null | awk -F/ 'NR>1 {print $1}')

    if [ -z "$PACKAGES" ]; then
        log "📋 Все пакеты актуальны, обновлять нечего."
    else
        log "📋 Доступны обновления для следующих пакетов:"
        echo "$PACKAGES" | awk '{print "  - " $1}'
    fi

    log "Полное обновление системы..."
    apt-get full-upgrade -y | tee /tmp/upgrade_log.txt >/dev/null 2>&1

    UPDATED=$(grep "Setting up" /tmp/upgrade_log.txt | awk '{print $3}')
    FAILED=$(grep -i "failed\|error" /tmp/upgrade_log.txt | awk '{print $NF}')

    echo "------------------------------------------------------------"
    echo "📌 Итог обновления:"

    if [ -n "$UPDATED" ]; then
        echo "✅ Успешно обновлены пакеты:"
        echo "$UPDATED" | awk '{print "  - " $1}'
    else
        echo "✅ Успешно обновлены пакеты: нет обновленных пакетов"
    fi

    if [ -n "$FAILED" ]; then
        echo "❌ Не удалось обновить:"
        echo "$FAILED" | awk '{print "  - " $1}'
    else
        echo "❌ Не удалось обновить: нет ошибок обновления"
    fi
    echo "------------------------------------------------------------"

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
        TOKEN=${TOKEN:-"Не найден"}
    else
        TOKEN="Не найден (папка логов отсутствует)"
    fi

    log "✅ Установка завершена!"

    echo "------------------------------------------------------------"
    echo "✅ TeamSpeak успешно установлен!"
    echo "🔹 Голосовой порт: $VOICE_PORT"
    echo "🔹 Порт передачи файлов: $FILETRANSFER_PORT"
    echo "🔹 Порт для запросов: $QUERY_PORT"
    echo "🔹 Статус сервиса: $(systemctl is-active teamspeak)"
    echo "🔹 Токен администратора: $TOKEN"
    echo "------------------------------------------------------------"

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

# Установка TeamSpeak
install_teamspeak
