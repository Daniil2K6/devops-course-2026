#!/usr/bin/env bash
set -uo pipefail
PASS=0; FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')";
        ((FAIL++))
    fi
}
echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo "[1] Служба SSH"
check "Вход от имени root запрещён"        "no"  "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no"  "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
check "Порт SSH отличен от 22"             "1"   "$(sudo sshd -T | awk '/^port/{print ($2 != 22)}')"
check "MaxAuthTries равен 3"               "3"   "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"
echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
check "Политика входящего трафика по умолчанию: deny" "deny" "$(sudo ufw status verbose | awk '/^Default:/{print $2}')"
echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx 2>/dev/null || true)"
check "Конфигурация nginx корректна" "0" "$(sudo nginx -t >/dev/null 2>&1; echo $?)"
check "Сертификат devops.crt действует не менее 30 дней" "0" "$(sudo openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend 2592000 >/dev/null 2>&1; echo $?)"
web_state="ok"
www_writable="$(sudo find /var/www/devops-site -perm -o+w 2>/dev/null || true)"
key_mode="$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null || true)"
if [[ -n "$www_writable" || "$key_mode" != "600" ]]; then
    web_state="нарушено (o+w: ${www_writable:-нет}; ключ: ${key_mode:-не определены})"
fi
check "Нет файлов с правом записи для всех, права ключа 600" "ok" "$web_state"
echo "[5] Контейнеризация"
check "Служба Docker активна" "active" "$(systemctl is-active docker 2>/dev/null || true)"
db_id="$(docker compose --project-directory "$HOME/app" ps -q db 2>/dev/null || true)"
check "Контейнер PostgreSQL healthy" "healthy" "$(docker inspect -f '{{.State.Health.Status}}' "$db_id" 2>/dev/null || true)"
port_state="unavailable"
if listeners="$(ss -tln 2>/dev/null)" &&
   app_port="$(docker compose --project-directory "$HOME/app" port app 5000 2>/dev/null)" &&
   db_bindings="$(docker inspect -f '{{with index .NetworkSettings.Ports "5432/tcp"}}{{range .}}{{println .HostIp}}{{end}}{{end}}' "$db_id" 2>/dev/null)"; then
    port_state="$(awk '$4 ~ /:(5000|5432)$/ && $4 !~ /^127\.0\.0\.1:/ {bad=1} END {print bad ? "exposed" : "loopback-only"}' <<< "$listeners")"
    if [[ "$app_port" != "127.0.0.1:5000" || -n "$db_bindings" ]]; then
        port_state="exposed-or-missing"
    fi
fi
check "Порты 5000 и 5432 не опубликованы во внешнюю сеть" "loopback-only" "$port_state"
check "Права ~/app/.env равны 600" "600" "$(stat -c '%a' "$HOME/app/.env" 2>/dev/null || true)"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
