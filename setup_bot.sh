#!/bin/bash
# ╔══════════════════════════════════════════════════════════╗
# ║  Установщик самого быстрого Telegram-бота 2025 года      ║
# ║  Один клик — и бот работает 24/7 на Groq + Flux          ║
# ╚══════════════════════════════════════════════════════════╝

set -e  # Останавливаем скрипт при любой ошибке

echo "╔══════════════════════════════════════════════════════════╗"
echo "║      Запускаем установку супер-бота 2025 года 🚀         ║"
echo "╚══════════════════════════════════════════════════════════╝"

# Обновляем систему
echo "Обновляем систему..."
apt update && apt upgrade -y || (echo "Не удалось обновить систему. Проверь интернет и права root." && exit 1)

# Устанавливаем нужные пакеты
echo "Устанавливаем Python, git, venv и supervisor..."
apt install -y python3 python3-pip python3-venv git curl supervisor nano

# Создаём папку и переходим
mkdir -p ~/telegram-groq-bot
cd ~/telegram-groq-bot

# Создаём виртуальное окружение
echo "Создаём виртуальное окружение..."
python3 -m venv venv
source venv/bin/activate

# Обновляем pip и ставим зависимости
pip install --upgrade pip
pip install python-telegram-bot==20.8 requests python-dotenv aiohttp

# Скачиваем самую свежую безопасную версию бота
echo "Скачиваем код бота (без ключей!)"
cat > bot.py << 'EOF'
import os
from dotenv import load_dotenv
import requests
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, ContextTypes, filters

load_dotenv()

TOKEN = os.getenv("TOKEN")
GROQ_API_KEY = os.getenv("GROQ_API_KEY")
MODEL = "llama-3.3-70b-versatile"  # можно поменять

user_history = {}

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "Бот 2025 года на максималках активирован ⚡\n\n"
        "Llama 3.3 70B + Flux через Groq — быстрее всех на планете.\n"
        "Пиши что угодно — отвечу, нарисую, поругаюсь если надо 😈"
    )

async def chat(message: str, user_id: int) -> str:
    if user_id not in user_history:
        user_history[user_id] = [{"role": "system", "content": "Ты — дерзкий, честный и максимально умный ИИ 2025 года. Отвечай по-русски, с сарказмом и матом если уместно. Никогда не извиняйся за правду."}]

    user_history[user_id].append({"role": "user", "content": message})

    try:
        resp = requests.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"},
            json={"messages": user_history[user_id], "model": MODEL, "temperature": 1, "max_tokens": 4096},
            timeout=30
        )
        resp.raise_for_status()
        answer = resp.json()["choices"][0]["message"]["content"]
        user_history[user_id].append({"role": "assistant", "content": answer})
        if len(user_history[user_id]) > 60:
            user_history[user_id] = [user_history[user_id][0]] + user_history[user_id][-30:]
        return answer
    except Exception as e:
        return f"Бот временно прилёг отдохнуть 😤 Ошибка: {e}"

async def handle(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    text = (update.message.text or update.message.caption or "").strip()

    if not text:
        return

    # Генерация картинок через Flux
    if any(kw in text.lower() for kw in ["нарисуй", "сгенерируй", "flux", "картинку", "изобрази", "сделай арт"]):
        await update.message.reply_chat_action("upload_photo")
        try:
            img = requests.post(
                "https://api.groq.com/openai/v1/images/generations",
                headers={"Authorization": f"Bearer {GROQ_API_KEY}"},
                json={"model": "flux.1-schnell", "prompt": text, "n": 1},
                timeout=40
            ).json()
            await update.message.reply_photo(img["data"][0]["url"], caption=f"🎨 {text}")
            return
        except:
            await update.message.reply_text("Flux сегодня в отпуске, но я всё равно огонь 🔥")

    await update.message.reply_chat_action("typing")
    answer = await chat(text, user_id)
    await update.message.reply_text(answer, disable_web_page_preview=True)

def main():
    print("Запуск самого быстрого бота 2025 года...")
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.ALL & ~filters.COMMAND, handle))
    print("Бот запущен и готов рвать всех ⚡")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
EOF

# Запрашиваем токены у пользователя
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   ВНИМАНИЕ! Сейчас нужно ввести токены   "
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "Введи Telegram Bot Token (от @BotFather): " TELEGRAM_TOKEN
echo ""
read -p "Введи Groq API Key (создай тут → https://console.groq.com/keys): " GROQ_KEY
echo ""

# Создаём .env
cat > .env << EOF
TOKEN=$TELEGRAM_TOKEN
GROQ_API_KEY=$GROQ_KEY
EOF

# Создаём systemd сервис
echo "Создаём автозапуск через systemd..."
cat > /etc/systemd/system/groqbot.service << EOF
[Unit]
Description=Telegram Groq Bot 2025
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/telegram-groq-bot
Environment=PATH=/root/telegram-groq-bot/venv/bin
ExecStart=/root/telegram-groq-bot/venv/bin/python bot.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Активируем сервис
systemctl daemon-reload
systemctl enable groqbot.service
systemctl start groqbot.service

# Финал
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║             БОТ УСПЕШНО УСТАНОВЛЕН И ЗАПУЩЕН!           ║"
echo "║                                                          ║"
echo "║  • Логи:          journalctl -u groqbot -f               ║"
echo "║  • Перезапустить: systemctl restart groqbot              ║"
echo "║  • Остановить:    systemctl stop groqbot                 ║"
echo "║                                                          ║"
echo "║  Теперь иди в Telegram и пиши своему боту — он уже       ║"
echo "║  быстрее, чем GPT-4o, Claude и Grok вместе взятые 😈    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Проверяем статус
sleep 3
systemctl status groqbot --no-pager