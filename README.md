# 🚀 Установка и управление скриптами

Добро пожаловать! Здесь представлены инструкции по установке и удалению серверов **TeamSpeak** и **Minecraft** с помощью удобных скриптов. ⬇️

---

## 🎙️ Установка и удаление TeamSpeak

### 📥 Установка TeamSpeak

Чтобы установить TeamSpeak, выполните следующую команду:

```bash
sh <(wget -O - https://raw.githubusercontent.com/IceOne-i/nikbellik-scripts/refs/heads/main/install_teamspeak.sh) -- 0000 0000 0000
```

🔹 **Примечание:** Замените `0000 0000 0000` на порты, которые вы хотите использовать. Обычно:
- Первый порт должен заканчиваться на `7`
- Второй порт — на `1`
- Третий порт — на `2`

### 🗑️ Удаление TeamSpeak

Если вам нужно удалить TeamSpeak, выполните команду:

```bash
sh <(wget -O - https://raw.githubusercontent.com/IceOne-i/nikbellik-scripts/refs/heads/main/install_teamspeak.sh) remove
```

---

## 🎮 Установка сервера Minecraft

### 📥 Запуск установки Minecraft

Для установки сервера Minecraft используйте следующую команду:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/IceOne-i/nikbellik-scripts/refs/heads/main/install_minecraft.sh)
```

---

## ℹ️ Дополнительная информация

📢 **Важно:**
- Все скрипты необходимо запускать от имени `root`.
- Оба скрипта автоматически обновят все пакеты на сервере перед установкой.
