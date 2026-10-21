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

## Восстановление после отката на снимок 01-clean-install

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
10. Проверить результат: `sudo sshd -T`, `sudo ss -tlnp | grep sshd`, `sudo ufw status verbose`, `hostname -f`, `ssh devops.local 'whoami; hostname -f'`, `bash scripts/audit.sh` (код возврата 0); при необходимости создать снимок `04-restored`.

Ориентировочное время восстановления — 10–15 минут.

## 8. Веб-сервер

- Пакет: `nginx` из репозитория Ubuntu; служба: `nginx.service`.
- Конфигурация ресурса: `/etc/nginx/sites-available/devops-site`; активная ссылка: `/etc/nginx/sites-enabled/devops-site`. Стандартная ссылка `default` отключена.
- Имя ресурса: `devops.local`; каталог сайта: `/var/www/devops-site`, владелец `devops:devops`.
- Права каталога сайта: `755`; права файлов: `644`. Пользователь рабочих процессов Nginx (`www-data`) имеет чтение и проход, но не запись.
- Сертификат: `/etc/ssl/certs/devops.crt`, права `644`; закрытый ключ: `/etc/ssl/private/devops.key`, владелец `root:root`, права `600`.
- Сертификат самоподписанный, RSA 2048 бит, срок действия 365 дней, SAN `DNS:devops.local`. Команда формирования:

  ```bash
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/devops.key \\
    -out /etc/ssl/certs/devops.crt \\
    -subj "/CN=devops.local" \\
    -addext "subjectAltName=DNS:devops.local"
  ```

- Блок HTTP перенаправляет запросы на `https://$host$request_uri` кодом 301. HTTPS-блок использует TLS 1.2/1.3 и собственные журналы `/var/log/nginx/devops-site.access.log` и `/var/log/nginx/devops-site.error.log`.
- После изменения конфигурации: `sudo nginx -t && sudo systemctl reload nginx`.
- Для восстановления полного состояния см. шаги в этом разделе и снимок `04-nginx-https`.
