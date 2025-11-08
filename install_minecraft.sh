#!/bin/bash
set -euo pipefail

### === Настройки ===
SCRIPT_VERSION="2.0"
MCSM_INSTALL_SCRIPT="https://script.mcsmanager.com/setup_cn.sh"
JAVA16_URL="https://download.java.net/openjdk/jdk16/ri/openjdk-16+36_linux-x64_bin.tar.gz"
JAVA16_DIR="/usr/lib/jvm/java-16-openjdk-amd64"
START_SCRIPT_PATH="/root/scripts/start.sh"

### === Цвета для вывода ===
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
RESET="\033[0m"

### === Лог-функции ===
log() { echo -e "➡ ${GREEN}$1${RESET}"; }
warn() { echo -e "⚠ ${YELLOW}$1${RESET}"; }
error_exit() { echo -e "❌ ${RED}$1${RESET}" >&2; exit 1; }

### === Проверка root ===
if [[ "$(id -u)" -ne 0 ]]; then
    error_exit "Скрипт должен быть запущен от root!"
fi

### === Проверка интернет-соединения ===
if ! ping -c1 -W1 google.com &>/dev/null; then
    warn "Нет подключения к интернету — некоторые установки могут завершиться ошибкой."
fi

### === Обновление системы ===
log "Обновление системы..."
apt-get update -qq
apt-get upgrade -y -qq

### === Установка необходимых пакетов ===
install_package() {
    if dpkg -s "$1" &>/dev/null; then
        log "$1 уже установлен, пропускаем..."
    else
        log "Установка $1..."
        apt-get install -y -qq "$1" >/dev/null 2>&1 || error_exit "Не удалось установить $1"
    fi
}

for pkg in wget unzip curl openjdk-8-jdk openjdk-17-jdk openjdk-22-jdk qemu-guest-agent; do
    install_package "$pkg"
done

systemctl enable qemu-guest-agent --now >/dev/null 2>&1

### === Установка MCSManager ===
if ! command -v mcsm &>/dev/null; then
    log "Установка MCSManager..."
    wget -qO- "$MCSM_INSTALL_SCRIPT" | bash >/dev/null 2>&1 || warn "⚠ Не удалось установить MCSManager (проверь доступность сайта)"
else
    log "MCSManager уже установлен"
fi

systemctl stop mcsm-web.service 2>/dev/null || true
systemctl disable mcsm-web.service 2>/dev/null || true

### === Установка Java 16 ===
if [[ ! -d "$JAVA16_DIR" ]]; then
    log "Установка Java 16..."
    wget -q "$JAVA16_URL" -O /tmp/java16.tar.gz
    mkdir -p /usr/lib/jvm
    tar -xzf /tmp/java16.tar.gz -C /usr/lib/jvm >/dev/null 2>&1
    mv /usr/lib/jvm/jdk-16 "$JAVA16_DIR"
    update-alternatives --install /usr/bin/java java "$JAVA16_DIR/bin/java" 1
    rm /tmp/java16.tar.gz
else
    log "Java 16 уже установлена"
fi

### === Создание стартового скрипта Minecraft ===
if [[ ! -f "$START_SCRIPT_PATH" ]]; then
    log "Создание скрипта запуска Minecraft..."
    mkdir -p /root/scripts
    cat <<'EOL' > "$START_SCRIPT_PATH"
#!/bin/bash
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "Использование: $0 <папка_сервера> <MIN_RAM_GB> <MAX_RAM_GB>"
  exit 1
fi

SERVER_DIR="${1%/}"
MIN_RAM="$2"
MAX_RAM="$3"

if ! [[ "$MIN_RAM" =~ ^[0-9]+$ && "$MAX_RAM" =~ ^[0-9]+$ ]]; then
  echo "Ошибка: объём RAM должен быть числом (ГБ)."
  exit 1
fi
if (( MIN_RAM > MAX_RAM )); then
  echo "Ошибка: MIN_RAM > MAX_RAM."
  exit 1
fi

AVAIL_GB=$(free -g | awk '/^Mem:/{print $7}')
if (( AVAIL_GB < MAX_RAM )); then
  echo "⚠ Внимание: свободно $AVAIL_GB GiB, запрашивается $MAX_RAM GiB."
fi

cd "$SERVER_DIR" || { echo "Папка $SERVER_DIR не найдена"; exit 1; }

JAR_FILE=$(find . -maxdepth 1 -type f -name "*.jar" \
           | grep -E "[0-9]+\.[0-9]+(\.[0-9]+)?-.*\.jar" \
           | head -n1 || true)

if [ -z "$JAR_FILE" ]; then
  echo "Ошибка: не найден jar-файл с версией в имени!"
  exit 1
fi

MC_VERSION=$(echo "$JAR_FILE" | grep -oE "[0-9]+\.[0-9]+(\.[0-9]+)?")
echo "Обнаружена версия Minecraft: $MC_VERSION"

get_java() {
  case "$1" in
    1.12*|1.13*|1.14*|1.15*) echo "/usr/lib/jvm/java-8-openjdk-amd64/bin/java" ;;
    1.16*|1.17*)             echo "/usr/lib/jvm/java-16-openjdk-amd64/bin/java" ;;
    1.18*|1.19*)             echo "/usr/lib/jvm/java-17-openjdk-amd64/bin/java" ;;
    1.20*|1.21*|1.22*)       echo "/usr/lib/jvm/java-22-openjdk-amd64/bin/java" ;;
    *)                       echo "java" ;;
  esac
}

JAVA_CMD=$(get_java "$MC_VERSION")
echo "Используется Java: $JAVA_CMD"

LAUNCH_CMD=(
  "$JAVA_CMD"
  "-Xms${MIN_RAM}G"
  "-Xmx${MAX_RAM}G"
  "-Dfile.encoding=UTF-8"
  "-jar" "$JAR_FILE"
  "nogui"
)

echo
echo "=== Команда запуска ==="
printf " %q" "${LAUNCH_CMD[@]}"
echo
echo "======================="
echo

exec "${LAUNCH_CMD[@]}"
EOL
    chmod +x "$START_SCRIPT_PATH"
else
    log "Скрипт start.sh уже существует, пропускаем."
fi

### === Предложение выключить сервер ===
echo -e "\n${YELLOW}🔴 Хотите выключить сервер? (y/n)${RESET}"
read -r shutdown_choice
case "$shutdown_choice" in
    y|Y) log "Выключение системы..."; shutdown -h now ;;
    n|N) log "Сервер остаётся включённым." ;;
    *) warn "Неверный выбор, сервер остаётся включённым." ;;
esac

log "✅ Установка завершена успешно (версия скрипта $SCRIPT_VERSION)"
