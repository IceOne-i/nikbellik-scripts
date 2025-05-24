# 📦 nikbellik-scripts

Скрипты автоматизации для установки и управления различными сервисами на Linux-серверах.

## 🧰 Общий утилитарный скрипт

Все основные скрипты используют общий файл утилит `common_utils.sh`, в котором содержатся:

- Логирование (`log`)
- Установка пакетов (`install_package`)
- Обновление системы (`update_and_upgrade_system`)
- Автообновление (`setup_auto_update`, `remove_auto_update`)
- Подтверждение выключения (`confirm_shutdown`)
---

## 🎧 Установка TeamSpeak Server

Скрипт автоматически создаёт пользователя, настраивает порты, systemd-сервис и выводит админ-токен.

### ✅ Установка

```bash
bash <(wget -qO- https://raw.githubusercontent.com/IceOne-i/nikbellik-scripts/refs/heads/main/install_teamspeak.sh) -- 962
```

- `962` — префикс из трёх цифр для портов:
  - Голосовой порт: `9627`
  - Порт передачи файлов: `9621`
  - Query-порт: `9622`

### ❌ Удаление

```bash
bash <(wget -qO- https://raw.githubusercontent.com/IceOne-i/nikbellik-scripts/refs/heads/main/install_teamspeak.sh) -- remove
```

---

## 🎮 Установка Minecraft Server

Скрипт автоматически скачивает и настраивает сервер Minecraft, устанавливает Java, создаёт скрипт запуска и предлагает выключение.

### ✅ Установка

```bash
bash <(wget -qO- https://raw.githubusercontent.com/IceOne-i/nikbellik-scripts/refs/heads/main/install_minecraft.sh)
```

---

## 📌 Примечания

- Все скрипты предназначены для Ubuntu 24.04.2 LTS.
- Для запуска требуется `root`-доступ.
- Скрипты автоматически обновляют пакеты перед установкой.
- Не требуется вручную скачивать файлы — всё запускается через `wget -qO-` или `curl -fsSL`.

---

## 🔗 Контакты

Автор: [IceOne-i](https://github.com/IceOne-i)
