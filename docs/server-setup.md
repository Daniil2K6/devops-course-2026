# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

- Наименование: devops-vm
- Оперативная память: 2048 МБ
- Количество ядер процессора: 2
- Объём диска: 25 ГБ (динамически расширяемый)
- Гипервизор: VirtualBox 7.2.4 (хост macOS, ARM64)
- Гостевая ОС: Ubuntu Server 24.04.5 LTS (ARM64)

## 2. Сетевые интерфейсы

| Адаптер | Тип | Адрес | Назначение |
|---------|-----|-------|------------|
| Адаптер 1 | NAT | 10.0.2.15 | Доступ к репозиториям пакетов (исходящий в Интернет) |
| Адаптер 2 | Host-only (vboxnet0) | 192.168.56.3 | Доступ с хостовой системы (HTTP, SSH по devops.local) |

Сегмент Host-only: 192.168.56.0/24, шлюз хоста: 192.168.56.1.

Локальное доменное имя: на хосте в `/etc/hosts` добавлена запись `192.168.56.3   devops.local`.
Полное доменное имя узла (`hostname -f`): `devops-vm.devops.local` (задано через `hostnamectl` и запись `127.0.1.1` в `/etc/hosts` гостя).

## 3. Правило проброса портов

| Параметр | Значение |
|----------|----------|
| Наименование | ssh |
| Протокол | TCP |
| Адрес хостовой системы | 127.0.0.1 |
| Порт хостовой системы | 2222 |
| Порт гостевой системы | 2222 |

## 4. Учётные записи

| Имя | Группы | Способ аутентификации |
|-----|--------|----------------------|
| student | sudo | Пароль (первичная установка, используется только до настройки ключей) |
| devops | sudo | Открытый ключ ed25519 (~/.ssh/devops_vm на хосте), парольная аутентификация отключена |

Права доступа: `~/.ssh` — 700, `~/.ssh/authorized_keys` — 600.

## 5. Служба SSH

- Порт: 2222
- Расположение конфигурации: `/etc/ssh/sshd_config.d/99-hardening.conf` (основной файл не изменён, резервная копия `/etc/ssh/sshd_config.backup`)
- Изменённые директивы:

| Директива | Значение | Назначение |
|-----------|----------|------------|
| Port | 2222 | Нестандартный порт |
| PermitRootLogin | no | Запрет входа от root |
| PasswordAuthentication | no | Отключение парольной аутентификации |
| PubkeyAuthentication | yes | Вход только по ключу |
| PermitEmptyPasswords | no | Запрет пустых паролей |
| MaxAuthTries | 3 | Ограничение попыток аутентификации |
| LoginGraceTime | 30 | Время на аутентификацию, с |
| AllowUsers | devops | Вход только под devops |
| X11Forwarding | no | Отключение проброса X11 |
| ClientAliveInterval | 300 | Интервал keep-alive, с |
| ClientAliveCountMax | 2 | Максимум keep-alive без ответа |

- Служба: `ssh.service` (enabled), `ssh.socket` disabled — иначе параметр Port игнорируется

## 6. Правила межсетевого экрана

- Политика по умолчанию: deny incoming, allow outgoing
- Правила:

| Правило | Порт | Комментарий |
|---------|------|-------------|
| limit | 2222/tcp | SSH rate-limited (блокировка при 6+ соединениях за 30 с) |
| allow | 80/tcp | HTTP (для практики № 6) |
| allow | 443/tcp | HTTPS |

- Логирование: medium (`ufw logging medium`), журнал `/var/log/ufw.log`
- IPv6: при включении UFW автоматически создаёт парные правила для IPv6; в `ufw status` они отображаются с пометкой `(v6)`

## 7. Снимки состояния

| Наименование | Момент создания |
|--------------|-----------------|
| 01-clean-install | После чистой установки ОС и обновлений |
| 02-keys-configured | После настройки пользователя devops, ключей и ~/.ssh/config |
| 03-ssh-hardened | После усиления SSH (задание 2); UFW настроен позднее |

## 8. Веб-сервер

Раздел описывает целевое состояние практики № 6: публикацию статического ресурса через Nginx, HTTPS с самоподписанным сертификатом и доставку содержимого средствами rsync. По результатам проверки 21.10.2026 на доступной ВМ `devops-vm` пакет `nginx` не установлен, каталог `/var/www/devops-site`, конфигурация ресурса и файл `~/devops.crt` на хосте отсутствуют. Настройки ниже ещё не применены и требуют выполнения на ВМ с правами root.

- Устанавливаемый пакет: `nginx` из репозитория Ubuntu 24.04; служба `nginx.service`.
- Конфигурация ресурса: `/etc/nginx/sites-available/devops-site`; активна символической ссылкой в `/etc/nginx/sites-enabled/`.
- Стандартный ресурс Nginx отключён: ссылка `/etc/nginx/sites-enabled/default` удалена, файл конфигурации сохранён.
- Каталог ресурса: `/var/www/devops-site`, владелец `devops:devops`. Каталоги имеют права `755`, файлы `644`; файлов с правом записи для всех нет. Пользователь `www-data` может читать ресурс, но не может изменять его.
- Сертификат: `/etc/ssl/certs/devops.crt`, владелец `root:root`, права `644`, поле SAN `DNS:devops.local`.
- Закрытый ключ: `/etc/ssl/private/devops.key`, владелец `root:root`, права `600`. Ключ не копируется за пределы `/etc/ssl/private` и не добавляется в репозиторий.
- Сертификат самоподписанный, срок действия — 365 дней. Заголовок HSTS не добавляется.

Команда формирования сертификата:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```

Конфигурация ресурса: блок для порта 80 перенаправляет запросы кодом `301` на HTTPS; блок для порта 443 использует сертификат и ключ, протоколы `TLSv1.2` и `TLSv1.3`, корень `/var/www/devops-site`, `index.html` и собственную страницу `404.html`. Журналы ресурса: `/var/log/nginx/devops-site.access.log` и `/var/log/nginx/devops-site.error.log`.

Применение конфигурации выполняется только после проверки синтаксиса:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Доверие к самоподписанному сертификату на хосте обеспечивается его получением по SSH и явным указанием клиенту:

```bash
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
curl --cacert ~/devops.crt -I https://devops.local
```

Доставка содержимого выполняется сценарием `scripts/deploy.sh`: он проверяет наличие `site/index.html`, отсутствие незафиксированных изменений Git, синхронизирует каталог `site/` с правами `D755,F644`, затем проверяет HTTPS с проверкой сертификата. Пробный запуск: `scripts/deploy.sh --dry-run`. Эквивалентная команда rsync:

```bash
rsync -avz --delete --chmod=D755,F644 \
  -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
  site/ devops:/var/www/devops-site/
```

Состояние после настройки фиксируется снимком `04-nginx-https`.

## 9. Восстановление после отката на снимок 01-clean-install

Откат возвращает машину к состоянию после установки: пользователя `devops`, ключей, усиления SSH, UFW и имени узла нет, а проброс портов может вернуться к гостевому порту 22. Порядок восстановления:

1. Остановить машину и восстановить снимок: `VBoxManage snapshot "devops-vm" restore "01-clean-install"` (или Средства → Снимки → Восстановить).
2. Запустить машину и проверить адреса: `ip -brief address` — на `enp0s9` ожидается `192.168.56.3`.
3. При необходимости вернуть проброс портов: для выключенной машины `VBoxManage modifyvm "devops-vm" --natpf1 "ssh,tcp,127.0.0.1,2222,,2222"`, для работающей — `VBoxManage controlvm "devops-vm" natpf1 "ssh,tcp,127.0.0.1,2222,,2222"`.
4. Подключиться под `student` (порт 2222 либо 22 в зависимости от правила) и создать пользователя: `sudo adduser devops`, `sudo usermod -aG sudo devops`.
5. Установить открытый ключ: `ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1`; проверить права: `chmod 700 ~/.ssh`, `chmod 600 ~/.ssh/authorized_keys`.
6. Разместить `/etc/ssh/sshd_config.d/99-hardening.conf` с директивами из раздела 5; в `/etc/ssh/sshd_config.d/50-cloud-init.conf` закомментировать `PasswordAuthentication yes`.
7. Проверить конфигурацию `sudo sshd -t`, затем отключить сокет и включить службу: `sudo systemctl disable --now ssh.socket`, `sudo systemctl enable --now ssh.service`, `sudo systemctl restart ssh`.
8. Задать имя узла и запись hosts: `sudo hostnamectl set-hostname devops-vm`; в `/etc/hosts` добавить `127.0.1.1 devops-vm.devops.local devops-vm`.
9. Настроить UFW в безопасном порядке: `sudo ufw allow 2222/tcp`, `sudo ufw allow 80/tcp`, `sudo ufw allow 443/tcp`, `sudo ufw default deny incoming`, `sudo ufw default allow outgoing`, `sudo ufw enable`, `sudo ufw delete allow 2222/tcp`, `sudo ufw limit 2222/tcp comment 'SSH rate-limited'`, `sudo ufw logging medium`.
10. Проверить результат: `sudo sshd -T`, `sudo ss -tlnp | grep sshd`, `sudo ufw status verbose`, `hostname -f`, `ssh devops.local 'whoami; hostname -f'`, `bash scripts/audit.sh`; код возврата 0 достигается после настройки веб-сервера (раздел 8) и контейнеризации (раздел 10), иначе соответствующие проверки завершатся ошибкой. При необходимости создать снимок `04-restored`.

Ориентировочное время восстановления — 10–15 минут.


## 10. Контейнеризация (практическая работа № 7)

Это план конфигурации. Проверка 21.10.2026 обнаружила, что на доступной ВМ Docker и каталог `/home/devops/app` отсутствуют. Применение настроек ниже пока не подтверждено.

- Docker Engine устанавливается из официального репозитория Docker для Ubuntu; служба: `docker.service`.
- Версия сервера фиксируется по команде `docker version --format '{{.Server.Version}}'` перед сдачей отчёта. Для контрольной работы № 2 требуется версия не ниже 28.0.
- Пользователь деплоя: `devops`; перед использованием Docker проверьте его членство в группе `docker` командой `id devops`.
- Каталог проекта на сервере: `/home/devops/app`.
- Файл `/home/devops/app/.env` содержит параметры PostgreSQL и имеет владельца `devops`, права `600`. Файл не переносится с хостовой системы и исключён из Git и контекста сборки.
- Приложение публикуется на `127.0.0.1:5000`; порт PostgreSQL `5432` не публикуется.
- Сеть Compose: `backend`. Именованный том `app_db_data` подключён к `/var/lib/postgresql/data` контейнера PostgreSQL.
- Сервисы Compose перезапускаются с политикой `unless-stopped`; приложение ожидает состояние `healthy` сервиса `db`.
- Обратный прокси: в HTTPS-блоке `/etc/nginx/sites-available/devops-site` location `/app/` направляет запросы на `http://127.0.0.1:5000/` и передаёт заголовки `Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`. После проверки `sudo nginx -t` применяется `sudo systemctl reload nginx`.
- Перед окончательной сдачей замените сведения о версии Docker и группе `devops` фактическим выводом команд на сервере.
