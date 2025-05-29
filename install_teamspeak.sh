#!/bin/bash
set -euo pipefail

#####################################
# install_teamspeak.sh
# Устанавливает или удаляет TeamSpeak 3 Server
# Запуск:
#   sh <(wget -qO- URL/common_utils.sh) -- <XXX|remove>
#####################################

# ------------------------------
# Подключаем утилиты
# ------------------------------
log "Загрузка общих утилит..."
source <(wget -qO- https://raw.githubusercontent.com/IceOne-i/nikbellik-scripts/refs/heads/main/common_utils.sh)
log "Утилиты загружены."

# ------------------------------
# Обработка аргументов
# ------------------------------
log "Разбор аргументов запуска: $*"
if [ "${1:-}" = "--" ]; then
    shift
    log "Разделитель '--' обнаружен, аргументы сдвинуты."
fi
case "${1:-}" in
    remove)
        log "Аргумент 'remove' => запуск удаления.";
        remove_teamspeak
        exit 0
        ;;
    [0-9][0-9][0-9])
        PREFIX="$1"
        log "Установочный режим: префикс портов = $PREFIX";
        ;;
    *)
        log "❌ Ошибка: неверный аргумент ($1)!";
        echo "Использование: $0 <XXX> (три цифры порта) или $0 remove";
        exit 1
        ;;
esac

# ------------------------------
# Проверка существующей установки
# ------------------------------
if [ -d "/opt/teamspeak" ]; then
    log "⚠ TeamSpeak уже установлен на /opt/teamspeak.";
    read -p "Хотите удалить текущую установку? (y/n): " yn
    case "$yn" in
        [Yy]*) log "Подтверждён удаление существующей установки."; remove_teamspeak; exit 0 ;;
        *)    log "Пропуск удаления. Выход."; exit 0 ;;
    esac
fi

# ------------------------------
# Функция установки TeamSpeak
# ------------------------------
install_teamspeak() {
    log "=== Начало установки TeamSpeak ==="

    log "Шаг 1: Обновление и апгрейд системы"
    update_and_upgrade_system

    log "Шаг 2: Установка зависимостей"
    install_package qemu-guest-agent
    install_package bzip2

    log "Шаг 3: Создание пользователя 'teamspeak'"
    useradd -mrd /opt/teamspeak teamspeak -s "$(which bash)" >/dev/null 2>&1 || \
        log "Пользователь teamspeak уже существует, пропуск."

    log "Шаг 4: Формирование портов"
    VOICE_PORT="${PREFIX}7"; log "  - Voice порт: $VOICE_PORT"
    FILETRANSFER_PORT="${PREFIX}1"; log "  - FileTransfer порт: $FILETRANSFER_PORT"
    QUERY_PORT="${PREFIX}2"; log "  - Query порт: $QUERY_PORT"

    log "Шаг 5: Скачивание и распаковка TeamSpeak"
    su - teamspeak -c "
      wget -q https://files.teamspeak-services.com/releases/server/3.13.7/teamspeak3-server_linux_amd64-3.13.7.tar.bz2 \
        -O /opt/teamspeak/teamspeak-server.tar.bz2 &&
      tar xvjf /opt/teamspeak/teamspeak-server.tar.bz2 -C /opt/teamspeak --strip-components 1 &&
      touch /opt/teamspeak/.ts3server_license_accepted
    " && log "  - Скачивание и распаковка завершены."

    log "Шаг 6: Создание systemd-сервиса"
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
    log "  - Файл сервиса создан: /etc/systemd/system/teamspeak.service"

    log "Шаг 7: Перезагрузка systemd и запуск сервиса"
    systemctl daemon-reload >/dev/null 2>&1 && \
        log "  - systemd перезагружен"
    systemctl enable --now teamspeak >/dev/null 2>&1 && \
        log "  - Сервис teamspeak включен и запущен"

    log "Шаг 8: Ожидание генерации логов (2 секунды)"
    sleep 2

    log "Шаг 9: Извлечение токена администратора"
    TOKEN=$(grep -i "token=" /opt/teamspeak/logs/* | head -n1 | sed -E 's/.*token=//') || \
        TOKEN="Не найден"
    log "  - Токен: $TOKEN"

    log "=== Установка завершена ==="
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

    log "Шаг 10: Настройка авто-обновления"
    setup_auto_update

    log "Шаг 11: Предложение выключения сервера"
    confirm_shutdown
    log "=== Конец установки ==="
}

# ------------------------------
# Запуск установки
# ------------------------------
install_teamspeak
