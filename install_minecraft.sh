#!/bin/bash

# Проверка, запущен ли скрипт от root
if [[ $(id -u) -ne 0 ]]; then
    echo -e "\033[1;31mОшибка: Скрипт должен быть запущен от root. Используйте sudo.\033[0m"
    exit 1
fi

echo "\033[1;32mНачало установки: $(date)\033[0m"

# Функция для логирования
log() {
    echo -e "\033[1;34m$(date) - $1\033[0m"
}

# Функция для проверки установки пакета
is_installed() {
    dpkg -l | grep -q "^ii  $1 "
}

# Функция для проверки существования файла
file_exists() {
    [[ -f "$1" ]]
}

# Обновление системы
log "Обновление системы"
apt-get update -y -qq >/dev/null 2>&1 && apt-get full-upgrade -y -qq >/dev/null 2>&1

# Установка qemu-guest-agent
if ! is_installed "qemu-guest-agent"; then
    log "Установка qemu-guest-agent"
    apt-get install -y -qq qemu-guest-agent >/dev/null 2>&1
else
    log "qemu-guest-agent уже установлен"
fi

# Установка MCSManager
log "Установка MCSManager"
sudo su -c "wget -qO- https://script.mcsmanager.com/setup_cn.sh | bash" >/dev/null 2>&1

# Отключение службы MCSManager
log "Отключение MCSManager"
systemctl stop mcsm-web.service
systemctl disable mcsm-web.service

# Установка необходимых пакетов
for package in wget unzip openjdk-8-jdk openjdk-17-jdk openjdk-21-jdk; do
    if ! is_installed "$package"; then
        log "Установка $package"
        apt-get install -y -qq "$package" >/dev/null 2>&1
    else
        log "$package уже установлен"
    fi
done

# Установка Java 16, если она не установлена
if [ ! -d "/usr/lib/jvm/java-16-openjdk-amd64" ]; then
    log "Загрузка и установка Java 16"
    wget -q https://download.java.net/openjdk/jdk16/ri/openjdk-16+36_linux-x64_bin.tar.gz
    mkdir -p /usr/lib/jvm
    sudo tar -xvf openjdk-16+36_linux-x64_bin.tar.gz -C /usr/lib/jvm >/dev/null 2>&1
    sudo mv /usr/lib/jvm/jdk-16 /usr/lib/jvm/java-16-openjdk-amd64
    sudo update-alternatives --install /usr/bin/java java /usr/lib/jvm/java-16-openjdk-amd64/bin/java 1
else
    log "Java 16 уже установлена"
fi

# Создание скрипта запуска Minecraft, если он не существует
if ! file_exists "/root/scripts/start.sh"; then
    log "Создание скрипта запуска Minecraft"
    mkdir -p /root/scripts/
    cat <<EOL > /root/scripts/start.sh
#!/bin/bash

if [[ \$# -ne 3 ]]; then
    echo "Использование: \$0 <папка_сервера> <мин_память> <макс_память>"
    exit 1
fi

SERVER_DIR=\$1
MIN_MEMORY=\$2
MAX_MEMORY=\$3

cd "\$SERVER_DIR" || { echo "Ошибка: указанная папка не существует!"; exit 1; }

JAR_FILE=\$(ls | grep -E "[0-9]+\.[0-9]+(\.[0-9]+)?-.*\.jar" | head -n 1)
if [[ -z "\$JAR_FILE" ]]; then
    echo "Не найден серверный файл Minecraft."
    exit 1
fi

MC_VERSION=\$(echo "\$JAR_FILE" | grep -oE "[0-9]+\.[0-9]+(\.[0-9]+)?")
echo "Обнаружена версия Minecraft: \$MC_VERSION"

get_java_version() {
    case "\$1" in
        1.12*|1.13*|1.14*|1.15*) echo "/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java" ;;
        1.16*|1.17*) echo "/usr/lib/jvm/java-16-openjdk-amd64/bin/java" ;;
        1.18*|1.19*) echo "/usr/lib/jvm/java-17-openjdk-amd64/bin/java" ;;
        1.20*|1.21*) echo "/usr/lib/jvm/java-21-openjdk-amd64/bin/java" ;;
        *) echo "java" ;;
    esac
}

JAVA_CMD=\$(get_java_version "\$MC_VERSION")
echo "Используется Java: \$JAVA_CMD"

\$JAVA_CMD -Dfile.encoding=UTF-8 -Xms\$MIN_MEMORY -Xmx\$MAX_MEMORY -jar "\$JAR_FILE" nogui
EOL
    chmod +x /root/scripts/start.sh
else
    log "Скрипт start.sh уже существует, пропускаем создание"
fi

# Спрашиваем, нужно ли перезагрузить систему
read -p "Перезагрузить систему сейчас? (y/n): " REBOOT
if [[ "\$REBOOT" == "y" ]]; then
    log "Перезагрузка системы"
    reboot
else
    log "Перезагрузка пропущена"
fi

log "\033[1;32mНастройка завершена\033[0m"
