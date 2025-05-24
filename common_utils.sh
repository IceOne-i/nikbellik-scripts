#!/bin/bash
# common_utils.sh - утилитарные функции для установки TeamSpeak и Minecraft
set -e  # Остановка при ошибке

# ------------------------------
# Проверка запуска от root
# ------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Скрипт должен быть запущен от имени root!"
    exit 1
fi

# ------------------------------
# Логирование
# ------------------------------
log() {
    echo "➡ $1"
}

# ------------------------------
# Установка пакета, если не установлен
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
# Показать список доступных обновлений
# ------------------------------
show_upgrade_info() {
    PACKAGES=$(apt list --upgradable 2>/dev/null | awk -F/ 'NR>1 {print $1}')
    if [ -z "$PACKAGES" ]; then
        log "📋 Все пакеты актуальны, обновлять нечего."
    else
        log "📋 Доступны обновления для следующих пакетов:"
        echo "$PACKAGES" | awk '{print "  - " $1}'
    fi
}

# ------------------------------
# Выполнить полное обновление системы и собрать отчёт
# ------------------------------
perform_upgrade() {
    log "Полное обновление системы..."
    apt-get full-upgrade -y | tee /tmp/upgrade_log.txt >/dev/null 2>&1

    UPDATED=$(grep "Setting up" /tmp/upgrade_log.txt | awk '{print $3}')
    FAILED=$(grep -i "failed\|error" /tmp/upgrade_log.txt | awk '{print $NF}')

    echo "------------------------------------------------------------"
    echo "📌 Итог обновления системы:"
    if [ -n "$UPDATED" ]; then
        echo "✅ Успешно обновлены пакеты:"
        echo "$UPDATED" | awk '{print "  - " $1}'
    else
        echo "✅ Нет обновлённых пакетов"
    fi
    if [ -n "$FAILED" ]; then
        echo "❌ Ошибки при обновлении:"
        echo "$FAILED" | awk '{print "  - " $1}'
    else
        echo "❌ Ошибок обновления нет"
    fi
    echo "------------------------------------------------------------"
}

# ------------------------------
# Обновление и апгрейд системы (комбинированная функция)
# ------------------------------
update_and_upgrade_system() {
    log "Обновление списка пакетов..."
    apt-get update -qq >/dev/null 2>&1
    show_upgrade_info
    perform_upgrade
}

# ------------------------------
# Настройка авто-обновления через cron
# ------------------------------
CRON_FILE="/etc/cron.d/auto_update_system"
setup_auto_update() {
    if [ -f "$CRON_FILE" ]; then
        log "Авто-обновление уже настроено, пропускаем..."
    else
        log "Настройка ежедневного авто-обновления системы..."
        cat <<EOT > "$CRON_FILE"
# Ежедневное обновление системы и перезагрузка при необходимости
0 3 * * * root apt-get update -qq && apt-get upgrade -y && \
    if [ -f /var/run/reboot-required ]; then reboot; fi
EOT
        chmod 644 "$CRON_FILE"
        log "✅ Авто-обновление настроено (ежедневно в 03:00)"
    fi
}

remove_auto_update() {
    if [ -f "$CRON_FILE" ]; then
        log "Удаление авто-обновления системы..."
        rm -f "$CRON_FILE"
        log "✅ Авто-обновление отключено."
    else
        log "Задача авто-обновления не найдена, пропускаем..."
    fi
}

# ------------------------------
# Предложение выключения системы
# ------------------------------
confirm_shutdown() {
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
                log "Сервер остаётся включённым."
                break
                ;;
            * )
                echo "❌ Пожалуйста, введите y или n"
                ;;
        esac
    done
}
