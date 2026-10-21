# Практическая работа № 7 — команды и разбор

## Подготовка проекта на хосте

1. Создать ветку `feature/docker` и каталог `app/`.
2. Использовать `app/app.py`, `app/requirements.txt`, `app/Dockerfile`, `app/.dockerignore`, `app/.env.example`, `app/docker-compose.yml` из этого репозитория. В `app/app.py` уже выполнена правка шага 1.6: `Hello from Docker, Baltaev!`.
3. Добавить `.env` в `.gitignore`. Фактический секрет создаётся только на сервере.
4. Проверить `git status`, затем зафиксировать и отправить ветку после завершения серверной части.

## Доставка и запуск на сервере

Из корня репозитория сначала выполнить план, затем доставку:

```bash
rsync -avz --delete --exclude=.env --dry-run app/ devops:app/
rsync -avz --delete --exclude=.env app/ devops:app/
```

На сервере:

```bash
cd ~/app
cp .env.example .env
chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
docker compose up -d --build
docker compose ps
for i in 1 2 3; do curl -s http://127.0.0.1:5000/; done
```

Ожидается здоровый сервис `db`, последовательное увеличение `Visits`, один опубликованный адрес `127.0.0.1:5000` и отсутствие опубликованного порта PostgreSQL. `docker compose down` сохраняет том `app_db_data`; `docker compose down -v` удаляет его вместе с данными.

## Сборка образа и контейнер без СУБД (шаги 1.4–1.6)

На сервере:

```bash
cd ~/app
docker build -t devops-app:1.0 .
docker image ls devops-app
docker history devops-app:1.0
docker run -d --name app-test -p 127.0.0.1:5000:5000 devops-app:1.0
docker ps
curl -i http://127.0.0.1:5000/health   # ожидается 200 OK
curl -i http://127.0.0.1:5000/          # ожидается 500 Internal Server Error
docker logs app-test                    # в журнале ошибка подключения к СУБД
docker exec app-test id                 # процесс от пользователя app, не root
docker rm -f app-test
```

В контейнере, запущенном без Compose, `localhost` указывает на сам контейнер приложения, где PostgreSQL нет; обращение к СУБД на сервере не может завершиться успешно, поскольку её порт не опубликован наружу. После правки `app.py` (шаг 1.6) сборка повторяется той же командой `docker build`: слои инструкций до `COPY app.py` отмечаются `CACHED`, пересоздаются только слой копирования кода и все последующие, поэтому повторная установка зависимостей не выполняется.

## Сеть, порты и сохранность данных (шаги 2.5–2.6)

Проверка разрешения имён и опубликованных портов:

```bash
docker network ls
docker compose exec app getent hosts db
sudo ss -tlnp | grep -E ':(5000|5432)\b'
```

Ожидается разрешение имени `db` в адрес сети проекта, сокет только `127.0.0.1:5000`, порт 5432 на сервере не прослушивается.

Сохранность данных:

```bash
docker compose down
docker volume ls                      # том app_db_data сохранён
docker compose up -d
curl -s http://127.0.0.1:5000/        # счётчик продолжает отсчёт
docker compose down -v                # только осознанно: удаляет том с данными
docker compose up -d
curl -s http://127.0.0.1:5000/        # счётчик начинается с 1
```

После `down -v` проект снова запущен, но база пуста. Шаг 2.7 — фиксация и отправка ветки с проверкой `git ls-files | grep -x 'app/.env'` (ожидается пустой вывод). Шаг 2.8 — снимок состояния `05-docker-compose`; проект, том с данными и снимки по завершении работы удалять не допускается.

## Обход межсетевого экрана (шаг 3.1)

```bash
# [VM]
docker run -d --rm --name exposed -p 5001:5000 devops-app:1.0
sudo ufw status | grep 5001            # ожидается пустой вывод: правила нет
sudo iptables -t nat -L DOCKER -n | grep 5001
# [Хост]
curl -s http://devops.local:5001/health # ожидается ok
# [VM]
docker stop exposed
```

Порт, опубликованный на адресе `0.0.0.0`, доступен с хостовой системы при отсутствии разрешающего правила UFW: Docker добавляет свои правила в цепочки nat до обработки пакетов правилами UFW. Доступ к приложению снаружи исключает публикация `127.0.0.1:5000:5000` из задания 2.

## Обратный прокси

В HTTPS-блоке существующего ресурса Nginx добавить:

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Применить только после успешной проверки `sudo nginx -t && sudo systemctl reload nginx`. Завершающий `/` в `proxy_pass` убирает префикс `/app/`, поэтому `/app/health` становится `/health` для Flask.

## Пояснения для отчёта

- В отдельном контейнере `localhost` — сам контейнер приложения. СУБД доступна по DNS-имени сервиса `db` внутри Compose-сети.
- `www-data`/процесс приложения не должен иметь права менять исходники; Dockerfile запускает Gunicorn под непривилегированным `app`.
- `127.0.0.1:5000:5000` ограничивает опубликованный порт loopback-интерфейсом сервера. UFW не всегда фильтрует опубликованные Docker-порты, поэтому ограничение должно быть в самом mapping.
- `depends_on: condition: service_healthy` ждёт готовности PostgreSQL, а не только запуска его процесса.
- `$$POSTGRES_USER` и `$$POSTGRES_DB` оставляют подстановку на момент выполнения healthcheck внутри контейнера; Compose не раскрывает их при чтении YAML.
- `docker compose down` оставляет именованный том; `down -v` удаляет его. Обновление major-версии PostgreSQL без миграции может сделать формат данных тома несовместимым.
- Процесс приложения запускается не от root: в Dockerfile это задаёт `USER app`. В контейнере PostgreSQL штатная точка входа запускает сервер БД от пользователя `postgres`.

## Проверка обратного прокси

```bash
curl --cacert ~/devops.crt https://devops.local/app/
curl --cacert ~/devops.crt https://devops.local/app/health
curl --cacert ~/devops.crt -I https://devops.local/
```

При остановленном приложении запрос через Nginx должен вернуть `502 Bad Gateway`; причина `connect() failed (111: Connection refused) while connecting to upstream` должна появиться в `/var/log/nginx/devops-site.error.log`.

Диагностика отказа (шаг 3.4):

```bash
# [VM]
cd ~/app && docker compose stop app
# [Хост]
curl --cacert ~/devops.crt -I https://devops.local/app/   # ожидается 502 Bad Gateway
# [VM]
sudo tail -n 3 /var/log/nginx/devops-site.error.log       # запись connect() failed (111: Connection refused)
docker compose start app
```

Отказ происходит на участке «Nginx — контейнер»: Nginx принимает соединение клиента, но приложение не слушает `127.0.0.1:5000`, поэтому соединение с upstream отклоняется ядром с `Connection refused`.

## Требования методички вне этих команд (шаги 3.5–3.7)

- Шаг 3.5: раздел `## 9. Контейнеризация` в `docs/server-setup.md` (способ установки Docker Engine и версия, участники группы docker, расположение проекта и `.env` с правами, публикуемые порты и адреса, именованные тома, конфигурация обратного прокси). Файл правится в объёме ПР №6 отдельным агентом.
- Шаг 3.6: раздел `[5] Контейнеризация` в `scripts/audit.sh` с четырьмя проверками через `check`: активна ли служба docker; `healthy` у `app-db-1`; порты 5000/5432 слушаются только на `127.0.0.1`; права `~/app/.env` равны 600. Файл правится тем же агентом.
- Шаг 3.7: Pull Request из `feature/docker` в `main` и слияние; ссылка на PR — в отчёте.

> Выполняйте реальные команды на ВМ и заполняйте отчёт собственными выводами и скриншотами. Значения счётчиков, статусы контейнеров и ссылки на Pull Request нельзя подменять ожидаемыми примерами.
