# ДЗ №1 — фундамент DevOps-инфраструктуры

Практическая работа выполнена на уже предоставленной учебной Ubuntu VM: Ansible настроил хост, Docker Compose развернул приложение, а Bash-скрипт проверил Docker.

## Архитектура

```text
VM:$VM_SSH_PORT       --> SSH
VM:80                 --> nginx (reverse proxy) --> app (Nginx: Hello World)
Ansible               --> Docker + Compose + deployer + /opt/app
Terraform             --> отдельные сеть + том + Nginx на :8080
```

Контейнер `nginx` — единственный контейнер с опубликованным портом `80`. Контейнер `app` не публикует порт на хост: он находится во внутренней bridge-сети `app_net`, а proxy обращается к нему по DNS-имени `app`.

## Состав проекта

| Путь | Назначение |
| --- | --- |
| `ansible/` | inventory, конфигурация Ansible и идемпотентный playbook установки Docker |
| `terraform/` | отдельные Docker-сеть, named volume и Nginx на нестандартном порту |
| `scripts/monitor.sh` | проверка systemd-сервиса, журнал при сбое и ошибки syslog за час |
| `compose/` | Nginx reverse proxy и внутреннее приложение с `Hello World` |
| `.env.example` | безопасный шаблон параметров подключения к VM |

## Переменные окружения для VM

Скопируйте шаблон и внесите значения своей VM

```bash
cp .env.example .env
# Отредактируйте VM_HOST, VM_USER и VM_SSH_PORT.
set -a
source .env
set +a
```

Переменные используются во всех командах ниже:

```text
VM_HOST      — адрес VM
VM_USER      — SSH-пользователь
VM_SSH_PORT  — SSH-порт
```

## Выполненные проверки

| Этап | Результат |
| --- | --- |
| Подключение Ansible | VM доступна по SSH, значения берутся из `.env` |
| Идемпотентность | повторный запуск playbook: `ok=11 changed=0 failed=0` |
| Docker Compose | `homework-app` — `healthy`; `homework-proxy` публикует `0.0.0.0:80->80/tcp` |
| Reverse proxy | на VM команда `curl http://$VM_HOST` вернула страницу `Hello World` |
| Мониторинг | `Status: active`, `Count: 0` для сервиса `docker` |
| Terraform Docker provider | созданы отдельные сеть, том и Nginx на `8080` |

## Скриншоты выполнения

| Скриншот | Что подтверждает |
| --- | --- |
| [Первый запуск Ansible](screenshots/ansible_first.png) | Установка и первичная настройка Docker-хоста |
| [Второй запуск Ansible](screenshots/ansible_second.png) | Идемпотентность: `changed=0`, `failed=0` |
| [Docker Compose](screenshots/docker_compose_work.png) | Запуск `app` и `nginx`; статус `healthy` у приложения |
| [Проверка curl](screenshots/curl_work.png) | Ответ `Hello World` через reverse proxy по IP VM |
| [Мониторинг Docker](screenshots/monitor_work.png) | Docker активен, ошибок syslog за последний час нет |
| [Terraform Nginx: HTTP-проверка](screenshots/curl_work_new.png) | `curl -i http://localhost:8080` возвращает `HTTP/1.1 200 OK` |
| [Terraform Nginx: Docker-объекты](screenshots/nginx_work.png) | Том, сеть, публикация `8080:80` и изоляция в `terraform-nginx-net` |
| [Terraform state](screenshots/terraform_state.png) | Terraform управляет image, container, network и volume |
| [Проверка с локальной машины](screenshots/local_machine_curl.png) | Доступ к Terraform-Nginx с ноутбука через SSH-туннель |

## 1. Terraform Docker provider: отдельный Nginx на :8080

Terraform использует `kreuzwerker/docker`, а не облачный провайдер. Конфигурация создаёт bridge-сеть `terraform-nginx-net`, named volume `terraform-nginx-html` и контейнер `terraform-nginx` из `nginx:1.27-alpine`. Он опубликован как `8080:80`.

Это окружение отделено от Compose: контейнеры `homework-proxy` и `homework-app` продолжают работать в сети `app_net` на порту `80`.

Terraform запускается на VM внутри одноразового контейнера `hashicorp/terraform`; ему передаётся Unix socket `/var/run/docker.sock`. Docker API наружу не открывается.

```bash
# На локальной машине, из корня проекта
set -a && source .env && set +a
scp -P "$VM_SSH_PORT" -r terraform "$VM_USER@$VM_HOST:/tmp/"

# На VM
ssh -p "$VM_SSH_PORT" "$VM_USER@$VM_HOST"
sudo install -d -o deployer -g deployer /opt/terraform-nginx
sudo cp -a /tmp/terraform/. /opt/terraform-nginx/
sudo chown -R deployer:deployer /opt/terraform-nginx
sudo -iu deployer
cd /opt/terraform-nginx
./bootstrap_provider.sh
./run_terraform.sh init
./run_terraform.sh apply
curl -i http://localhost:8080
docker network inspect terraform-nginx-net
docker volume inspect terraform-nginx-html
```

Скрипт `bootstrap_provider.sh` скачивает официальный GitHub-релиз Docker provider и сверяет SHA-256. Он нужен только потому, что учебная VM не может обратиться к `registry.terraform.io`. `run_terraform.sh` запускает Terraform в фиксированном контейнере и не требует копировать длинную `docker run` команду в терминал.

Фактическая проверка вернула `HTTP/1.1 200 OK` и страницу `Welcome to nginx!`. У контейнера `terraform-nginx` опубликовано `0.0.0.0:8080->80/tcp`; `docker inspect` подтвердил, что он подключён только к `terraform-nginx-net`. `docker volume inspect` подтвердил local volume `terraform-nginx-html`.

## 2. Настройка VM через Ansible

Inventory не содержит IP: хост имеет псевдоним `app-vm`, а `ansible_host`, пользователь и порт читаются из переменных окружения. Из корня проект запустить 

```bash
set -a && source .env && set +a
cd ansible
ansible all -m ping --ask-pass
ansible-playbook setup_host.yml --ask-pass --ask-become-pass
ansible-playbook setup_host.yml --ask-pass --ask-become-pass
```

`ansible.cfg` хранит временные файлы Ansible в `ansible/.ansible/`, а не в домашнем каталоге контроллера. Первый запуск устанавливает Docker Engine и Compose plugin, включает сервис Docker, создаёт пользователя `deployer`, добавляет его в группу `docker`, выдаёт passwordless sudo и создаёт `/opt/app`. Второй запуск не меняет уже настроенный хост (`changed=0`), что подтверждает идемпотентность.

Предупреждения Ansible о будущем удалении `apt_repository` и об инъекции facts не являются ошибками: оба запуска закончились без `failed`.

## 3. Docker Compose

С локальной машины скопировать каталог Compose и запустить из корня:

```bash
set -a && source .env && set +a
scp -P "$VM_SSH_PORT" -r compose "$VM_USER@$VM_HOST:/tmp/"
ssh -p "$VM_SSH_PORT" -t "$VM_USER@$VM_HOST" \
  'sudo cp -a /tmp/compose/. /opt/app/ &&
   sudo chown -R deployer:deployer /opt/app &&
   sudo -iu deployer bash -lc "cd /opt/app && docker compose up -d && docker compose ps"'
```

Проверка на VM:

```bash
ssh -p "$VM_SSH_PORT" "$VM_USER@$VM_HOST"
curl "http://$VM_HOST"
sudo -iu deployer bash -lc 'cd /opt/app && docker compose ps'
```

Ожидается HTML-страница с `Hello World`, а у `app` должен быть статус `healthy`.

### Проверка с локальной машины через SSH-туннель

Учебная инфраструктура блокирует прямой входящий TCP/80 и TCP/8080 снаружи. Сервисы на VM работают, что подтверждают `curl` на VM и `docker ps`, но проверку с ноутбука можно безопасно выполнить через SSH-туннель, не открывая firewall.

В первом терминале на локальной машине:

```bash
# из корня проекта
set -a && source .env && set +a
ssh -N -p "$VM_SSH_PORT" -L 8080:localhost:8080 "$VM_USER@$VM_HOST"
```

Оставить это соединение открытым. Во втором терминале:

```bash
curl -i http://localhost:8080
```

Запрос должен вернуть `HTTP/1.1 200 OK` от Terraform-Nginx. SSH-туннель передаёт локальный порт `8080` через уже разрешённый SSH-порт VM; он не делает Docker-порт публично доступным.

Для Compose-приложения можно аналогично использовать локальный порт `8081`:

```bash
ssh -N -p "$VM_SSH_PORT" -L 8081:localhost:80 "$VM_USER@$VM_HOST"
curl http://localhost:8081
```

## 4. Мониторинг

Скопировать скрипт и запустить из корня:

```bash
set -a && source .env && set +a
scp -P "$VM_SSH_PORT" scripts/monitor.sh "$VM_USER@$VM_HOST:/tmp/"
ssh -p "$VM_SSH_PORT" -t "$VM_USER@$VM_HOST" 'chmod +x /tmp/monitor.sh && sudo /tmp/monitor.sh docker'
```

Фактический результат:

```text
== Service: docker ==
Status: active
-- Errors in /var/log/syslog during the last hour --
Count: 0
```

`monitor.sh` принимает имя сервиса, безопасно валидирует его, вызывает `systemctl is-active`, а при неактивном сервисе показывает последние 10 строк `journalctl`. Затем связка `grep` и `awk` считает записи `error`, `failed` и `critical` в `/var/log/syslog` за последние 60 минут. Значение `Count: 0` — корректный результат: за час ошибок не найдено.
