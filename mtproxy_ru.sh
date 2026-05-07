#!/usr/bin/env bash

set -euo pipefail

DB_DIR="/opt/mtproxy-bridge"
DB_FILE="$DB_DIR/clients.db"
QR_DIR="$DB_DIR/qrcodes"
SERVICE_PREFIX="mtproxy-forward"
SOCAT_BIN="/usr/bin/socat"

mkdir -p "$DB_DIR" "$QR_DIR"
touch "$DB_FILE"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Запусти скрипт от root."
    exit 1
  fi
}

detect_pkg_manager() {
  if command -v apt >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  else
    echo ""
  fi
}

install_package_if_missing() {
  local cmd="$1"
  local pkg="$2"

  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi

  local pm
  pm="$(detect_pkg_manager)"

  if [[ -z "$pm" ]]; then
    echo "Не найден пакетный менеджер (apt/dnf/yum). Установи $pkg вручную."
    exit 1
  fi

  echo "Устанавливаю пакет: $pkg"

  case "$pm" in
    apt)
      apt update
      DEBIAN_FRONTEND=noninteractive apt install -y "$pkg"
      ;;
    dnf)
      dnf install -y "$pkg"
      ;;
    yum)
      yum install -y "$pkg"
      ;;
  esac
}

ensure_dependencies() {
  install_package_if_missing "socat" "socat"
  install_package_if_missing "qrencode" "qrencode"

  if [[ ! -x "$SOCAT_BIN" ]]; then
    SOCAT_BIN="$(command -v socat)"
  fi
}

get_ru_ip() {
  local ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -z "${ip:-}" ]]; then
    ip="$(curl -4 -s ifconfig.me || true)"
  fi
  echo "$ip"
}

port_in_use() {
  local port="$1"
  if ss -ltn | awk '{print $4}' | grep -Eq "(^|:)$port$"; then
    return 0
  fi
  return 1
}

client_exists() {
  local name="$1"
  grep -q "^${name}|" "$DB_FILE"
}

service_name() {
  local name="$1"
  echo "${SERVICE_PREFIX}-${name}.service"
}

service_file() {
  local name="$1"
  echo "/etc/systemd/system/$(service_name "$name")"
}

save_client() {
  local name="$1"
  local eu_ip="$2"
  local eu_port="$3"
  local ru_ip="$4"
  local ru_port="$5"
  local secret="$6"

  echo "${name}|${eu_ip}|${eu_port}|${ru_ip}|${ru_port}|${secret}" >> "$DB_FILE"
}

delete_client_from_db() {
  local name="$1"
  grep -v "^${name}|" "$DB_FILE" > "${DB_FILE}.tmp"
  mv "${DB_FILE}.tmp" "$DB_FILE"
}

get_client_line() {
  local name="$1"
  grep "^${name}|" "$DB_FILE" || true
}

print_link_and_qr() {
  local name="$1"
  local ru_ip="$2"
  local ru_port="$3"
  local secret="$4"

  local link="tg://proxy?server=${ru_ip}&port=${ru_port}&secret=${secret}"
  local png_file="${QR_DIR}/${name}.png"

  echo
  echo "Ссылка:"
  echo "$link"
  echo

  qrencode -o "$png_file" "$link"

  echo "QR-код:"
  qrencode -t ANSIUTF8 "$link"
  echo
  echo "PNG сохранён: $png_file"
  echo
}

create_service() {
  local name="$1"
  local eu_ip="$2"
  local eu_port="$3"
  local ru_port="$4"
  local svc_file
  svc_file="$(service_file "$name")"

  cat > "$svc_file" <<EOF
[Unit]
Description=MTProxy forward for ${name}
After=network.target

[Service]
Type=simple
ExecStart=${SOCAT_BIN} TCP-LISTEN:${ru_port},fork,reuseaddr TCP:${eu_ip}:${eu_port}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$(service_name "$name")"
}

remove_service() {
  local name="$1"
  local svc
  local svc_file
  svc="$(service_name "$name")"
  svc_file="$(service_file "$name")"

  systemctl stop "$svc" 2>/dev/null || true
  systemctl disable "$svc" 2>/dev/null || true
  rm -f "$svc_file"
  systemctl daemon-reload
}

check_eu_reachable() {
  local eu_ip="$1"
  local eu_port="$2"

  if command -v nc >/dev/null 2>&1; then
    if ! nc -z -w 3 "$eu_ip" "$eu_port"; then
      echo "Предупреждение: EU ${eu_ip}:${eu_port} сейчас не отвечает."
    fi
  else
    echo "nc не найден, пропускаю проверку доступности EU."
  fi
}

create_client() {
  local name eu_ip eu_port secret ru_port ru_ip

  echo "Введите имя клиента:"
  read -r name

  if [[ -z "$name" ]]; then
    echo "Имя клиента не может быть пустым."
    return
  fi

  if client_exists "$name"; then
    echo "Клиент с таким именем уже существует."
    return
  fi

  echo "Введите EU IP:"
  read -r eu_ip

  echo "Введите EU PORT:"
  read -r eu_port

  echo "Введите SECRET:"
  read -r secret

  echo "Введите RU PORT:"
  read -r ru_port

  if [[ -z "$eu_ip" || -z "$eu_port" || -z "$secret" || -z "$ru_port" ]]; then
    echo "Все поля обязательны."
    return
  fi

  if port_in_use "$ru_port"; then
    echo "Порт $ru_port уже занят на RU сервере."
    return
  fi

  ru_ip="$(get_ru_ip)"
  check_eu_reachable "$eu_ip" "$eu_port"
  create_service "$name" "$eu_ip" "$eu_port" "$ru_port"
  save_client "$name" "$eu_ip" "$eu_port" "$ru_ip" "$ru_port" "$secret"

  echo
  echo "Клиент создан:"
  echo "Имя: $name"
  echo "Маршрут: ${ru_ip}:${ru_port} -> ${eu_ip}:${eu_port}"

  print_link_and_qr "$name" "$ru_ip" "$ru_port" "$secret"
}

list_clients() {
  if [[ ! -s "$DB_FILE" ]]; then
    echo "Список клиентов пуст."
    return
  fi

  echo
  echo "Список клиентов:"
  echo

  awk -F'|' '{printf "Имя: %s | RU: %s:%s -> EU: %s:%s\n", $1, $4, $5, $2, $3}' "$DB_FILE"
  echo
}

show_client_link() {
  local name line client eu_ip eu_port ru_ip ru_port secret

  echo "Введите имя клиента:"
  read -r name

  line="$(get_client_line "$name")"
  if [[ -z "$line" ]]; then
    echo "Клиент не найден."
    return
  fi

  IFS='|' read -r client eu_ip eu_port ru_ip ru_port secret <<< "$line"

  echo
  echo "Клиент: $client"
  echo "RU: ${ru_ip}:${ru_port}"
  echo "EU: ${eu_ip}:${eu_port}"

  print_link_and_qr "$client" "$ru_ip" "$ru_port" "$secret"
}

delete_client() {
  local name line client eu_ip eu_port ru_ip ru_port secret png_file

  echo "Введите имя клиента для удаления:"
  read -r name

  line="$(get_client_line "$name")"
  if [[ -z "$line" ]]; then
    echo "Клиент не найден."
    return
  fi

  IFS='|' read -r client eu_ip eu_port ru_ip ru_port secret <<< "$line"

  remove_service "$client"
  delete_client_from_db "$client"

  png_file="${QR_DIR}/${client}.png"
  rm -f "$png_file"

  echo "Клиент $client удалён."
}

show_status() {
  if [[ ! -s "$DB_FILE" ]]; then
    echo "Список клиентов пуст."
    return
  fi

  while IFS='|' read -r client eu_ip eu_port ru_ip ru_port secret; do
    local svc
    svc="$(service_name "$client")"
    echo "========================================"
    echo "Клиент: $client"
    echo "Маршрут: ${ru_ip}:${ru_port} -> ${eu_ip}:${eu_port}"
    systemctl --no-pager --full status "$svc" | sed -n '1,8p' || true
    echo
  done < "$DB_FILE"
}

main_menu() {
  while true; do
    echo "=============================="
    echo " MTProxy RU Manager"
    echo "=============================="
    echo "1. Создать клиента"
    echo "2. Список клиентов"
    echo "3. Показать ссылку и QR клиента"
    echo "4. Удалить клиента"
    echo "5. Статус сервисов"
    echo "0. Выход"
    echo
    echo "Выбери пункт:"
    read -r choice

    case "$choice" in
      1) create_client ;;
      2) list_clients ;;
      3) show_client_link ;;
      4) delete_client ;;
      5) show_status ;;
      0) exit 0 ;;
      *) echo "Неверный пункт меню." ;;
    esac
  done
}

require_root
ensure_dependencies
main_menu
