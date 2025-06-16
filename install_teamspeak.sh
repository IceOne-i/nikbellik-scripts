#!/bin/bash
set -e

#####################################
# install_teamspeak.sh
# Устанавливает или удаляет TeamSpeak 3 Server
# Запуск:
#   bash <(wget -qO- URL/install_teamspeak.sh) -- <XXX|remove>
#####################################

# ------------------------------
# Подключаем утилиты
# ------------------------------
source <(wget -qO- https://raw.githubusercontent.com/IceOne-i/nikbellik-scripts/refs/heads/main/common_utils.sh)

# ------------------------------
# Функция удаления TeamSpeak
# ------------------------------
remove_teamspeak() {
    log "Начало удаления TeamSpeak..."

    # Останавливаем и отключаем сервис
    systemctl stop teamspeak    >/dev/null 2>&1 || true
    systemctl disable teamspeak >/dev/null 2>&1 || true

    # Удаляем пользователя и файлы
    userdel -r teamspeak        >/dev/null 2>&1 || true
    rm -rf /opt/teamspeak
    rm -f /etc/systemd/system/teamspeak.service
    systemctl daemon-reload     >/dev/null 2>&1

    # Удаляем крон задачу автообновления
    log "Удаление авто-обновления системы..."
    remove_auto_update

    log "✅ TeamSpeak успешно удален."
}

# ------------------------------
# Функция установки TeamSpeak
# ------------------------------
install_teamspeak() {
    log "=== Начало установки TeamSpeak ==="

    log "1. Обновление и апгрейд системы"
    update_and_upgrade_system

    log "2. Установка зависимостей"
    install_package qemu-guest-agent
    install_package bzip2

    log "3. Создание пользователя teamspeak"
    useradd -mrd /opt/teamspeak teamspeak -s "$(which bash)" >/dev/null 2>&1 || \
        log "Пользователь teamspeak уже существует, пропуск."

    log "4. Формирование портов"
    VOICE_PORT="${PREFIX}7"; log "  - Voice: $VOICE_PORT"
    FILETRANSFER_PORT="${PREFIX}1"; log "  - FileTransfer: $FILETRANSFER_PORT"
    QUERY_PORT="${PREFIX}2"; log "  - Query: $QUERY_PORT"

    log "5. Скачивание и распаковка TeamSpeak"
    su - teamspeak -c "
      wget -q https://files.teamspeak-services.com/releases/server/3.13.7/teamspeak3-server_linux_amd64-3.13.7.tar.bz2 \
        -O /opt/teamspeak/teamspeak-server.tar.bz2 &&
      tar xvjf /opt/teamspeak/teamspeak-server.tar.bz2 -C /opt/teamspeak --strip-components 1 &&
      touch /opt/teamspeak/.ts3server_license_accepted
    " && log "  - Скачивание и распаковка завершены"

    log "6. Создание systemd-сервиса"
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
    log "  - Файл сервиса создан"

    log "7. Перезапуск systemd и запуск сервиса"
    systemctl daemon-reload >/dev/null 2>&1 && log "  - systemd перезагружен"
    systemctl enable --now teamspeak >/dev/null 2>&1 && log "  - Сервис включен и запущен"

    log "8. Ожидание генерации логов"
    sleep 2

    log "9. Извлечение токена администратора"
    TOKEN=$(grep -i "token=" /opt/teamspeak/logs/* | head -n1 | sed -E 's/.*token=//')
    log "  - Админ-токен: $TOKEN"

    log "=== Установка завершена ==="
    cat <<EOF
------------------------------------------------------------
✅ TeamSpeak установлен!
🔹 Voice порт: $VOICE_PORT
🔹 FileTransfer порт: $FILETRANSFER_PORT
🔹 Query порт: $QUERY_PORT
🔹 Статус: $(systemctl is-active teamspeak)
🔹 Токен: $TOKEN
------------------------------------------------------------
EOF

    log "10. Настройка авто-обновления"
    setup_auto_update

    log "11. Предложение выключения"
    confirm_shutdown
    log "=== Конец установки ==="
}

# ------------------------------
# Обработка аргументов
# ------------------------------
if [ "${1:-}" = "--" ]; then shift; fi
case "${1:-}" in
    remove)
        remove_teamspeak; exit 0
        ;;
    [0-9][0-9][0-9])
        PREFIX="$1"
        ;;
    *)
        echo "❌ Ошибка: нужно указать префикс (XXX) или 'remove'"
        exit 1
        ;;
esac

# ------------------------------
# Проверка существующей установки
# ------------------------------
if [ -d "/opt/teamspeak" ]; then
    log "⚠ TeamSpeak уже установлен"
    read -p "Удалить текущую установку? (y/n): " yn
    case "$yn" in
        [Yy]*) remove_teamspeak; exit 0 ;;
        *) exit 0 ;;
    esac
fi

# Запуск установки
install_teamspeak
