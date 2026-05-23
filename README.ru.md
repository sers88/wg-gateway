# wg-gateway

[![Build](https://github.com/ksantd/wg-gateway/actions/workflows/docker.yml/badge.svg)](https://github.com/ksantd/wg-gateway/actions/workflows/docker.yml)
[![Release](https://github.com/ksantd/wg-gateway/actions/workflows/release.yml/badge.svg)](https://github.com/ksantd/wg-gateway/actions/workflows/release.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/ksantd/wg-gateway)](https://hub.docker.com/r/ksantd/wg-gateway)
[![MIT License](https://img.shields.io/github/license/ksantd/wg-gateway)](LICENSE)

[English](README.md)

**WireGuard VPN-шлюз с маршрутизацией трафика через прокси по правилам.**

Единый Docker-образ, объединяющий управление WireGuard-сервером, прокси/маршрутизацию (Mihomo) и веб-интерфейсы для обоих компонентов. Клиенты WireGuard подключаются, и весь их трафик проходит через прокси-движок, где на основе правил каждое соединение направляется через **прокси** или **напрямую** в интернет.

## Архитектура

```
                       ┌──────────────────────────────────────────┐
                       │          wg-gateway container            │
                       │                                          │
  WireGuard  ──udp──► │  wg0 ──policy routing──► Mihomo TUN      │
  клиент               │         (таблица 666)     │              │
                       │                           ├─► PROXY ──► Прокси-сервер ──► Интернет
                       │                           │              │
                       │                           └─► DIRECT ──► Интернет
                       │                                          │
                       │  wg-easy UI (:51821)  Mihomo UI (:51888) │
                       └──────────────────────────────────────────┘
```

### Маршрутизация трафика

1. Клиент WireGuard подключается к серверу на **UDP 51820**.
2. Расшифрованный трафик появляется на интерфейсе **wg0** внутри контейнера.
3. Правило policy routing (`ip rule`, приоритет 200) перехватывает трафик из подсети WireGuard и направляет его в отдельную таблицу маршрутизации (666).
4. Эта таблица отправляет весь трафик через **TUN-устройство Mihomo**.
5. Mihomo применяет правила (домены, IP CIDR, GeoIP, rule-providers и т.д.) и решает для каждого соединения: **PROXY** или **DIRECT**.
6. Трафик DIRECT выходит через реальный сетевой интерфейс хоста. Трафик PROXY — через настроенный прокси-сервер.
7. Исходящие соединения самого Mihomo используют основную таблицу маршрутизации, избегая зацикливания.

Фоновый демон маршрутизации отслеживает интерфейсы и автоматически восстанавливает policy routing и правила iptables при перезапуске Mihomo или wg-easy.

### Почему используется host network

Режим хост-сети необходим, потому что:

- **wg-easy** управляет интерфейсом `wg0` WireGuard напрямую на хосте.
- **Mihomo TUN** создаёт виртуальное сетевое устройство, перехватывающее трафик на уровне ядра.
- **Policy routing** (`ip rule`, `ip route`) работает с таблицами маршрутизации хоста.
- Мостовая сеть добавила бы лишние слои NAT и усложнила бы настройку прозрачного прокси.

## Быстрый старт

### Docker run

```bash
docker run -d \
  --name wg-gateway \
  --restart unless-stopped \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv6.conf.all.forwarding=1 \
  --device /dev/net/tun:/dev/net/tun \
  -v /path/to/wireguard:/data/wireguard \
  -v /path/to/mihomo:/data/mihomo \
  -v /path/to/ui:/data/ui \
  -v /path/to/logs:/data/logs \
  -e WG_HOST=YOUR_SERVER_PUBLIC_IP \
  -e WG_EASY_INIT_PASSWORD=YOUR_ADMIN_PASSWORD \
  ksantd/wg-gateway:latest
```

### Docker Compose

```bash
cp .env.example .env
# Отредактируйте .env и укажите WG_HOST — публичный IP вашего сервера
docker compose up -d
```

## Необходимые capabilities и sysctl

| Параметр | Значение | Зачем |
|---|---|---|
| `--network host` | Хост-сеть | WireGuard, TUN и маршрутизация требуют доступа уровня хоста |
| `--cap-add NET_ADMIN` | Linux capability | Создание сетевых интерфейсов и изменение таблиц маршрутизации |
| `--cap-add SYS_MODULE` | Linux capability | Загрузка модуля ядра `wireguard`, если требуется |
| `--sysctl net.ipv4.ip_forward=1` | Параметр ядра | Включает IPv4-форвардинг между интерфейсами |
| `--sysctl net.ipv6.conf.all.forwarding=1` | Параметр ядра | Включает IPv6-форвардинг |
| `--device /dev/net/tun` | Доступ к устройству | Требуется Mihomo для создания TUN-интерфейса |

**Требования к хосту:** в ядре должен быть доступен модуль `wireguard`. На большинстве современных дистрибутивов Linux он включён. На Unraid убедитесь, что установлен плагин WireGuard.

## Порты

| Порт | Протокол | Сервис |
|---|---|---|
| 51820 | UDP | WireGuard VPN-сервер |
| 51821 | TCP | wg-easy Web UI (управление пирами) |
| 51888 | TCP | Web UI прокси-движка (дашборд Mihomo) |

## Тома

| Точка монтирования | Назначение |
|---|---|
| `/data/wireguard` | Конфигурация WireGuard и данные пиров |
| `/data/mihomo` | Конфигурация прокси-движка |
| `/data/ui` | Опционально: пользовательские UI-ассеты (по умолчанию используется встроенный UI) |
| `/data/logs` | Лог-файлы |

## Первый запуск

wg-easy v15 поддерживает два режима настройки:

### Автоматическая настройка (рекомендуется)

Если в `.env` заданы `WG_HOST` и `WG_EASY_INIT_PASSWORD`, контейнер автоматически конфигурируется при первом запуске:

1. Запустите контейнер.
2. Откройте **wg-easy UI** по адресу `http://IP_ВАШЕГО_СЕРВЕРА:51821` и войдите с учётными данными из `.env`.
3. Создайте клиента/пир WireGuard.
4. Скачайте сгенерированный файл `.conf` или отсканируйте QR-код.
5. Импортируйте конфигурацию в клиент WireGuard (телефон, ноутбук и т.д.).
6. Подключитесь — ваш трафик теперь идёт через шлюз.

### Ручная настройка (мастер)

Если `WG_HOST` не задан или `WG_EASY_INIT_PASSWORD` пуст, при первом запуске откроется мастер настройки Web UI. Откройте `http://IP_ВАШЕГО_СЕРВЕРА:51821` и следуйте инструкциям на экране.

> **Примечание:** По умолчанию **весь трафик идёт напрямую** (без прокси). Чтобы направить трафик через прокси, отредактируйте конфигурацию Mihomo (см. ниже).

## Доступ к веб-интерфейсам

- **wg-easy** (управление WireGuard-пирами): `http://IP_ВАШЕГО_СЕРВЕРА:51821`
- **Дашборд прокси-движка**: `http://IP_ВАШЕГО_СЕРВЕРА:51888/ui/`

## Настройка правил прокси

### Редактирование конфигурации

Конфигурация Mihomo находится в `/data/mihomo/config.yaml`. Отредактируйте его, чтобы добавить прокси и правила.

### Добавление прокси вручную

```yaml
proxies:
  - name: "my-proxy"
    type: ss
    server: server.example.com
    port: 443
    cipher: aes-256-gcm
    password: "secret"
```

Затем добавьте его в группу PROXY:

```yaml
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - my-proxy
      - DIRECT
```

### Использование подписки (proxy-provider)

```yaml
proxy-providers:
  my-sub:
    type: http
    url: "https://ваша-подписка"
    interval: 3600
    path: /data/mihomo/providers/my-sub.yaml
    health-check:
      enable: true
      url: http://www.gstatic.com/generate_204
      interval: 300

proxy-groups:
  - name: PROXY
    type: select
    use:
      - my-sub
    proxies:
      - DIRECT
```

### Изменение поведения маршрутизации

По умолчанию правило `MATCH,DIRECT` в конце списка означает, что весь неперехваченный трафик идёт напрямую. Чтобы направлять весь трафик через прокси по умолчанию:

```yaml
rules:
  - DOMAIN-SUFFIX,local,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - MATCH,PROXY    # <-- Изменено с DIRECT на PROXY
```

### Применение изменений

После редактирования `config.yaml` перезагрузите конфигурацию через дашборд `:51888/ui/` или перезапустите Mihomo:

```bash
docker exec wg-gateway supervisorctl restart mihomo
```

Демон маршрутизации автоматически восстановит policy routes при пересоздании TUN-устройства.

## Переменные окружения

### Обязательные

| Переменная | По умолчанию | Описание |
|---|---|---|
| `WG_HOST` | _(нет — обязательно)_ | Публичный IP или hostname для конфигурации клиентов. Также используется как `INIT_HOST` для автоматической настройки wg-easy. |
| `WG_EASY_INIT_PASSWORD` | _(нет — обязательно для автоматической настройки)_ | Пароль в открытом виде (не bcrypt-хеш) для учётной записи администратора wg-easy. Создаётся один раз при первом запуске. |

### Опциональные

| Переменная | По умолчанию | Описание |
|---|---|---|
| `WG_PORT` | `51820` | UDP-порт WireGuard-сервера (используется для `INIT_PORT`) |
| `WG_DEFAULT_DNS` | `1.1.1.1` | DNS, назначаемый клиентам WireGuard (используется для `INIT_DNS`) |
| `WG_ALLOWED_IPS` | `0.0.0.0/0,::/0` | Маршруты, назначаемые клиентам (используется для `INIT_ALLOWED_IPS`) |
| `WG_EASY_PORT` | `51821` | Порт Web UI wg-easy |
| `WG_EASY_INIT_USERNAME` | `admin` | Имя администратора wg-easy (используется один раз при первом запуске) |
| `INSECURE` | `true` | Разрешить HTTP-доступ к wg-easy UI (установите `false` только за HTTPS reverse proxy) |
| `MIHOMO_PORT` | `51888` | Порт external controller прокси-движка |
| `MIHOMO_SECRET` | _(пусто)_ | Секрет для API прокси-движка |
| `TUN_DEV` | `Meta` | Имя TUN-устройства Mihomo |
| `ROUTE_CHECK_INTERVAL` | `30` | Интервал проверки правил iptables (секунды) |
| `ROUTE_WAIT` | `90` | Максимальное время ожидания интерфейсов (секунды) |
| `TZ` | `UTC` | Часовой пояс |

## Развёртывание на Unraid

### Предварительные требования

- Установите плагин **WireGuard** из Unraid Community Applications (если ещё не установлен).
- Убедитесь, что `/dev/net/tun` существует (обычно есть на Unraid 6.x+).

### Вариант A: Docker CLI (рекомендуется)

```bash
docker run -d \
  --name wg-gateway \
  --restart unless-stopped \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv6.conf.all.forwarding=1 \
  --device /dev/net/tun:/dev/net/tun \
  -v /mnt/user/appdata/wg-gateway/wireguard:/data/wireguard \
  -v /mnt/user/appdata/wg-gateway/mihomo:/data/mihomo \
  -v /mnt/user/appdata/wg-gateway/ui:/data/ui \
  -v /mnt/user/appdata/wg-gateway/logs:/data/logs \
  -e WG_HOST=YOUR_PUBLIC_IP \
  -e WG_EASY_INIT_PASSWORD=YOUR_ADMIN_PASSWORD \
  ksantd/wg-gateway:latest
```

### Вариант B: Шаблон Community Applications

1. В Unraid перейдите на вкладку **Docker** → **Add Container**.
2. Установите **Repository** в `ksantd/wg-gateway`.
3. Установите **Network Type** в **host**.
4. В **Extra Parameters** добавьте:
   ```
   --cap-add NET_ADMIN --cap-add SYS_MODULE --device /dev/net/tun:/dev/net/tun
   ```
5. Добавьте sysctl и монтирование томов, как в примере CLI выше.
6. Установите `WG_HOST` на ваш публичный IP и `WG_EASY_INIT_PASSWORD` на надёжный пароль.

### Специфика Unraid

- **Не** используйте встроенный менеджер WireGuard в Unraid вместе с этим контейнером на одном порту — они конфликтуют.
- Если у вас уже активен WireVPN в Unraid, остановите его или используйте другой порт для wg-gateway.
- Контейнер использует policy routing, ограниченный подсетью WireGuard и отдельной таблицей маршрутизации (666). Это не влияет на обычную сеть Unraid.
- **Цепочка FORWARD**: Docker на Unraid устанавливает политику `iptables FORWARD` в `DROP` по умолчанию. Контейнер добавляет явные правила `ACCEPT` для интерфейса `wg0`. Если клиенты подключаются, но нет интернета, проверьте: `iptables -L FORWARD -n` — должны быть записи `ACCEPT` для `wg0`.
- Просмотр логов: `docker exec wg-gateway cat /data/logs/supervisord.log`
- Проверка маршрутизации: `docker exec wg-gateway ip rule list` и `docker exec wg-gateway ip route show table 666`

## Известные ограничения

- **Только Linux/amd64** — образ собран специально для x86_64 Linux-хостов.
- **Аутентификация** — Web UI прокси-движка (`MIHOMO_SECRET`) имеет опциональный секрет API. wg-easy v15 требует учётные данные: укажите `WG_EASY_INIT_USERNAME`/`WG_EASY_INIT_PASSWORD` для автоматической настройки или задайте их через мастер Web UI при первом запуске.
- **Один интерфейс WireGuard** — wg-easy управляет одним интерфейсом `wg0`.
- **Нет split-tunnel со стороны сервера** — весь клиентский трафик проходит через шлюз. Клиенты могут управлять split-tunneling через `AllowedIPs` в своей конфигурации WireGuard.
- **Зависимость от порядка запуска** — демон маршрутизации ждёт появления обоих интерфейсов wg0 и Mihomo TUN и периодически повторяет попытки. Если один из сервисов не запустится, клиентский трафик не будет проксироваться до восстановления.
- **Требуется модуль ядра** — на хосте должен быть модуль `wireguard`. Это стандартно для современных ядер, но на некоторых минимальных дистрибутивах может потребоваться ручная установка.

## Сторонние компоненты

Проект включает следующее стороннее ПО. Полный текст лицензий см. в [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

| Компонент | Лицензия | Источник |
|---|---|---|
| wg-easy | AGPL-3.0 | https://github.com/wg-easy/wg-easy |
| Mihomo | GPL-3.0 | https://github.com/MetaCubeX/mihomo |
| metacubexd | MIT | https://github.com/MetaCubeX/metacubexd |

Данный проект распространяется под лицензией [MIT](LICENSE).

## Лицензия проекта

MIT — см. [LICENSE](LICENSE).
