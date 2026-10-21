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

rsync "${RSYNC_ARGS[@]}" "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"
curl --fail --silent --show-error --cacert "$CA_CERT" "$SITE_URL" --output /dev/null
printf 'Деплой выполнен успешно. Коммит: %s\n' "$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
