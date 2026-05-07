#!/usr/bin/env bash

set -euo pipefail

REPO="https://raw.githubusercontent.com/evgen1114/tgproxy-manager/main"
TARGET="/usr/local/bin/tproxy-ru"
TMP_FILE="/tmp/tproxy_ru.sh"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запусти от root:"
  echo "sudo bash <(curl -fsSL $REPO/install_ru.sh)"
  exit 1
fi

echo "[1/5] Создаю директории..."
mkdir -p /opt/mtproxy-bridge/qrcodes

echo "[2/5] Создаю базу клиентов..."
touch /opt/mtproxy-bridge/clients.db

echo "[3/5] Скачиваю RU-скрипт..."
curl -fsSL "$REPO/tproxy_ru.sh" -o "$TMP_FILE"

echo "[4/5] Устанавливаю в $TARGET ..."
install -m 755 "$TMP_FILE" "$TARGET"
rm -f "$TMP_FILE"

echo "[5/5] Готово."
echo "Запускаю tproxy-ru..."
exec /usr/local/bin/tproxy-ru
