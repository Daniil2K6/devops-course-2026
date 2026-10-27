#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"
DRY_RUN=false

if [[ $# -gt 1 ]]; then
    echo "Использование: $0 [--dry-run]" >&2
    exit 2
fi
if [[ $# -eq 1 ]]; then
    if [[ "$1" != "--dry-run" ]]; then
        echo "Неизвестный аргумент: $1" >&2
        echo "Использование: $0 [--dry-run]" >&2
        exit 2
    fi
    DRY_RUN=true
fi

if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: ${LOCAL_DIR}index.html не найден; доставка отменена." >&2
    exit 1
fi

if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения; доставка отменена." >&2
    exit 1
fi

RSYNC_ARGS=(-avz --delete --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if [[ "$DRY_RUN" == true ]]; then
    rsync "${RSYNC_ARGS[@]}" --dry-run "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"
    exit 0
fi

if [[ ! -r "$CA_CERT" ]]; then
    echo "Ошибка: доверенный сертификат не найден: $CA_CERT" >&2
    exit 1
fi

if ! rsync "${RSYNC_ARGS[@]}" "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"; then
    echo "Ошибка синхронизации; доставка не завершена." >&2
    exit 1
fi

# Явная запись hosts исключает конфликт .local с mDNS на macOS.
# Проверка имени SAN и доверия к сертификату сохраняется.
SITE_IP="${DEPLOY_SITE_IP:-$(awk '$1 !~ /^#/ {for (i=2;i<=NF;i++) if ($i=="devops.local") {print $1;exit}}' /etc/hosts)}"
CURL_ARGS=(--fail --silent --show-error --connect-timeout 5 --max-time 15 --cacert "$CA_CERT")
if [[ -n "$SITE_IP" ]]; then
    CURL_ARGS+=(--resolve "devops.local:443:${SITE_IP}")
fi
if ! curl "${CURL_ARGS[@]}" "$SITE_URL" --output /dev/null; then
    echo "Ошибка проверки HTTPS после доставки." >&2
    exit 1
fi
printf 'Деплой выполнен успешно. Коммит: %s\n' "$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
