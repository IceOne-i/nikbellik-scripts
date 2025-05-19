#!/bin/bash
set -e  # Остановка при ошибке

CRON_FILE="/etc/cron.d/auto_update_system"

# ------------------------------
# Общие функции логирования
# ------------------------------
log() {
    echo "➡ $1"
}

# ------------------------------
# Авто‑обновление системы
# ------------------------------
setup_auto_update() {
    if [ -f "$CRON_FILE" ]; then
        log "Авто‑обновление уже настроено, пропускаем..."
    else
        log "Настройка ежедневного авто‑обновления системы..."
        cat <<EOT > "$CRON_FILE"
# Ежедневное обновление системы и перезагрузка при необходимости
0 3 * * * root apt-get update -qq && apt-get upgrade -y && \
    if [ -f /var/run/reboot-required ]; then reboot; fi
EOT
        chmod 644 "$CRON_FILE"
        log "✅ Авто‑обновление настроено (ежедневно в 03:00 МСК)"
    fi
}

remove_auto_update() {
    if [ -f "$CRON_FILE" ]; then
        log "Удаление авто‑обновления системы..."
        rm -f "$CRON_FILE"
        log "✅ Авто‑обновление отключено."
    else
        log "Задача авто‑обновления не найдена, пропускаем..."
    fi
}

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

    # Удаляем авто‑обновление
    remove_auto_update

    log "✅ TeamSpeak успешно удален!"
}

# ------------------------------
# Установка необходимых пакетов
# ------------------------------
install_package() {
    if dpkg -s "$1" &> /dev/null; then
        log "$1 уже установлен, пропускаем..."
    else
        log "Установка пакета: $1"
        apt-get install -y -qq "$1" >/dev/null 2>&1
    fi
}

# ------------------------------
# Основная функция установки
# ------------------------------
install_teamspeak() {
    log "Обновление списка пакетов..."
    apt-get update -qq >/dev/null 2>&1

    PACKAGES=$(apt list --upgradable 2>/dev/null | awk -F/ 'NR>1 {print $1}')
    if [ -z "$PACKAGES" ]; then
        log "Все пакеты актуальны."
    else
        log "Доступны обновления для следующих пакетов:"
        echo "$PACKAGES" | awk '{print "  - " $1}'
    fi

    log "Полное обновление системы..."
    apt-get full-upgrade -y | tee /tmp/upgrade_log.txt >/dev/null 2>&1

    UPDATED=$(grep "Setting up" /tmp/upgrade_log.txt | awk '{print $3}')
    FAILED=$(grep -i "failed\|error" /tmp/upgrade_log.txt | awk '{print $NF}')

    echo "------------------------------------------------------------"
    echo "📌 Итог обновления системы:"
    if [ -n "$UPDATED" ]; then
        echo "✅ Обновлены пакеты:"
        echo "$UPDATED" | awk '{print "  - " $1}'
    else
        echo "✅ Обновлены пакеты: нет"
    fi
    if [ -n "$FAILED" ]; then
        echo "❌ Ошибки при обновлении:"
        echo "$FAILED" | awk '{print "  - " $1}'
    else
        echo "❌ Ошибок обновления: нет"
    fi
    echo "------------------------------------------------------------"

    install_package qemu-guest-agent
    install_package bzip2

    log "Создание пользователя teamspeak..."
    useradd -mrd /opt/teamspeak teamspeak -s "$(which bash)" >/dev/null 2>&1 || true

    # Параметры портов
    VOICE_PORT="${PREFIX}7"
    FILETRANSFER_PORT="${PREFIX}1"
    QUERY_PORT="${PREFIX}2"

    log "Скачивание и распаковка TeamSpeak..."
    su - teamspeak -c "
        wget -q https://files.teamspeak-services.com/releases/server/3.13.7/teamspeak3-server_linux_amd64-3.13.7.tar.bz2 -O /opt/teamspeak/teamspeak-server.tar.bz2 &&
        tar xvfj /opt/teamspeak/teamspeak-server.tar.bz2 -C /opt/teamspeak --strip-components 1 &&
        touch /opt/teamspeak/.ts3server_license_accepted
    " >/dev/null 2>&1

    log "Создание systemd‑сервиса для TeamSpeak..."
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

    # Получение токена
    if ls /opt/teamspeak/logs/ >/dev/null 2>&1; then
        TOKEN=$(grep -i "token=" /opt/teamspeak/logs/* | sed -E 's/.*token=//')
        TOKEN=${TOKEN:-"Не найден"}
    else
        TOKEN="Не найден (папка логов отсутствует)"
    fi

    log "✅ Установка TeamSpeak завершена!"
    echo "------------------------------------------------------------"
    echo "✅ TeamSpeak успешно установлен!"
    echo "🔹 Голосовой порт: $VOICE_PORT"
    echo "🔹 Порт передачи файлов: $FILETRANSFER_PORT"
    echo "🔹 Порт запросов: $QUERY_PORT"
    echo "🔹 Статус сервиса: $(systemctl is-active teamspeak)"
    echo "🔹 Токен администратора: $TOKEN"
    echo "------------------------------------------------------------"

    # Настраиваем авто‑обновление
    setup_auto_update

    # Предложение выключения
    while true; do
        printf "\033[32;1m🔴 Хотите выключить сервер? (y/n)\033[0m\n"
        read -r shutdown_choice
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

# ------------------------------
# Точка входа
# ------------------------------
# Проверка аргумента
if [ $# -ne 1 ] && [ "$1" != "remove" ]; then
    echo "❌ Ошибка: требуется один аргумент!"
    echo "Использование для установки: $0 <XXX> (первые три цифры порта)"
    echo "Использование для удаления: $0 remove"
    exit 1
fi

# Удаление
if [ "$1" == "remove" ]; then
    remove_teamspeak
    exit 0
fi

# Параметр префикса
PREFIX=$1
if ! [[ $PREFIX =~ ^[0-9]{3}$ ]]; then
    echo "❌ Ошибка: префикс должен состоять из трёх цифр"
    exit 1
fi

# Проверяем, не установлено ли уже
if [ -d "/opt/teamspeak" ]; then
    printf "\033[33;1m⚠ TeamSpeak уже установлен!\033[0m\n"
    printf "\033[32;1mХотите удалить его? (y/n)\033[0m\n"
    while true; do
        read -r choice
        case "$choice" in
            y|Y )
                remove_teamspeak
                exit 0
                ;;
            n|N )
                echo "🚪 Выход."
                exit 0
                ;;
            * )
                echo "❌ Введите y или n"
                ;;
        esac
    done
fi

# Установка
install_teamspeak
