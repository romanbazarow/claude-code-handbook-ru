# Установка и настройка OpenClaw на MacBook Pro (Intel)

Простая пошаговая инструкция: как поставить [OpenClaw](https://openclaw.ai/) на
**второй** ноутбук MacBook Pro (процессор **Intel**), войти по подписке **Claude
Pro** и подключить **Telegram-бота**, который будет вашим личным ассистентом.

> Инструкция рассчитана на **отдельную (standalone)** установку — свой Gateway
> прямо на этом ноутбуке, без подключения к другому компьютеру.

## Содержание

- [Что такое OpenClaw](#что-такое-openclaw)
- [Что понадобится](#что-понадобится)
- [Шаг 1. Установка одной командой](#шаг-1-установка-одной-командой)
- [Шаг 2. Онбординг (мастер настройки)](#шаг-2-онбординг-мастер-настройки)
- [Шаг 3. Gateway как фоновая служба](#шаг-3-gateway-как-фоновая-служба-демон)
- [Шаг 4. Проверка](#шаг-4-проверка)
- [Шаг 5. Подключение Telegram-бота](#шаг-5-подключение-telegram-бота-личный-ассистент)
- [Управление и настройка агента](#управление-и-настройка-агента)
- [Добавление и использование скиллов](#добавление-и-использование-скиллов)
- [Быстрые команды (шпаргалка)](#быстрые-команды-шпаргалка)
- [Частые проблемы на Intel Mac](#частые-проблемы-на-intel-mac)
- [Полезные ссылки](#полезные-ссылки)

---

## Что такое OpenClaw

OpenClaw — это self-hosted (запускаемый у себя) персональный AI-ассистент. Он
поднимает локальную фоновую службу — **Gateway** (порт `18789`), — через которую
агент работает и подключается к каналам (Telegram, CLI и т. д.).

На Intel-Mac всё работает штатно. Единственное отличие от Apple Silicon: Homebrew
ставится в `/usr/local` (а не в `/opt/homebrew`) — это пригодится в разделе
[про проблемы](#частые-проблемы-на-intel-mac).

## Что понадобится

- **macOS** на MacBook Pro (Intel) и доступ в интернет.
- Приложение **Terminal** (Терминал).
- Активная подписка **Claude Pro** — по ней будем авторизовывать агента.
- **Node.js вручную ставить не нужно** — установщик поставит нужную версию сам
  (OpenClaw требует Node 24; скрипт при необходимости подтянет Homebrew и Node).

---

## Шаг 1. Установка одной командой

Откройте Terminal и выполните:

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

Скрипт сам определит систему, при необходимости установит Homebrew и Node 24,
поставит OpenClaw и запустит мастер онбординга.

## Шаг 2. Онбординг (мастер настройки)

Если мастер не запустился автоматически — запустите его вручную:

```bash
openclaw onboard
```

Пройдите шаги мастера:

1. **Режим настройки** — выберите **QuickStart** (быстрый старт с разумными
   значениями по умолчанию: Gateway на порту `18789`, token-auth, только локальный
   доступ). Advanced нужен только для тонкой ручной настройки.
2. **Провайдер модели** — выберите **Anthropic**.
3. **Способ входа** — так как у вас подписка **Claude Pro**, выберите вход
   **через логин Claude CLI** (локальная сессия) или **setup-token**:
   - если на этом Mac уже установлен Claude Code и вы вошли под своей подпиской —
     OpenClaw просто переиспользует этот логин;
   - если нет — пройдите **setup-token flow** (мастер даст ссылку/код для входа).

> ⚠️ **Не выбирайте вариант «Anthropic API key».** API-ключ — это отдельная
> оплата по факту использования (pay-as-you-go) и подписку Claude Pro он **не**
> задействует. Для работы по подписке нужен именно вход через Claude CLI /
> setup-token.
>
> Учтите также, что запросы OpenClaw расходуют лимиты вашей подписки Claude Pro.

## Шаг 3. Gateway как фоновая служба (демон)

Чтобы Gateway работал в фоне и не выключался после закрытия Terminal, установите
его как службу:

```bash
openclaw onboard --install-daemon
```

Можно и отдельной командой:

```bash
openclaw gateway install
```

На macOS будет установлен **LaunchAgent** — Gateway поднимется автоматически и
переживёт закрытие терминала и перезагрузку.

## Шаг 4. Проверка

Убедитесь, что всё поднялось:

```bash
openclaw --version          # версия CLI — значит, установка прошла
openclaw doctor             # проверка конфигурации, без ошибок
openclaw gateway status     # статус Gateway — должно быть running
openclaw models status      # авторизация провайдера — профиль активен
```

Если `openclaw doctor` не показывает ошибок, а `gateway status` = `running` —
базовая установка готова.

---

## Шаг 5. Подключение Telegram-бота (личный ассистент)

Так вы сможете общаться с ассистентом прямо из Telegram.

### 5.1. Создать бота

В Telegram напишите официальному боту [@BotFather](https://t.me/BotFather)
(проверьте, что имя точно `@BotFather`):

1. Отправьте команду `/newbot`.
2. Задайте отображаемое имя и username бота.
3. Скопируйте и сохраните **токен**, который выдаст BotFather.

> 🔒 Токен — как пароль: кто угодно с ним может управлять вашим ботом. Держите его
> в секрете. Если утёк — сделайте `/revoke` у BotFather и получите новый.

### 5.2. Прописать токен и доступ

Добавьте канал Telegram в конфиг OpenClaw (`~/.openclaw/openclaw.json`),
секция `channels.telegram`:

```json5
{
  channels: {
    telegram: {
      enabled: true,
      botToken: "ВАШ_ТОКЕН",
      dmPolicy: "pairing",
      allowFrom: ["ВАШ_TELEGRAM_ID"],
    },
  },
}
```

- `allowFrom` — ваш **числовой Telegram ID**, чтобы с ботом не мог говорить кто
  попало. Узнать ID можно так: запустите `openclaw logs --follow`, напишите боту
  любое сообщение и посмотрите ID в логе.
- Альтернатива токену в конфиге — переменная окружения
  `TELEGRAM_BOT_TOKEN=ваш_токен` (работает для аккаунта по умолчанию).
  Приоритет источников токена: `tokenFile` > `botToken` > переменная окружения.

### 5.3. Перезапустить Gateway

Чтобы канал подхватился, перезапустите Gateway:

```bash
openclaw gateway restart
```

### 5.4. Спаривание (pairing)

Напишите своему боту в Telegram любое сообщение, затем на Mac подтвердите доступ:

```bash
openclaw pairing list telegram            # показать ожидающие коды
openclaw pairing approve telegram <КОД>   # подтвердить свой код
```

Коды действуют **1 час**. После подтверждения бот начнёт отвечать вам как
ассистент.

---

## Управление и настройка агента

- **Главный конфиг** — `~/.openclaw/openclaw.json`. Читать и менять значения
  удобнее командами, а не руками:

  ```bash
  openclaw config get <ключ>
  openclaw config set <ключ> <значение>
  ```

- **Применить изменения конфига** — перезапустить Gateway:

  ```bash
  openclaw gateway restart
  # полный цикл при необходимости:
  openclaw gateway stop && openclaw gateway start
  ```

- **Диагностика и здоровье:**

  ```bash
  openclaw doctor --fix              # проверка + авто-починка типовых проблем
  openclaw status --deep             # живые пробы всех подключённых каналов
  openclaw logs --follow --local-time  # лог в реальном времени, время в вашей зоне
  ```

- **Настройки самого агента** (модель, поведение, доступные скиллы) живут в
  секциях `agents.defaults` и `agents.list[]` в `openclaw.json`. Сменить
  провайдера или перелогиниться — снова `openclaw onboard`; проверить
  авторизацию — `openclaw models status`.

## Добавление и использование скиллов

**Скилл** — это папка с файлом `SKILL.md` (YAML-фронтматтер + markdown-инструкция),
которая учит агента новой способности и объясняет, когда её применять.

```bash
openclaw skills                 # список установленных скиллов (= skills list)
openclaw skills install <имя>   # установить скилл из ClawHub
openclaw skills install <имя> --global   # в общий ~/.openclaw/skills для всех агентов
openclaw skills check           # проверить корректность скиллов (после апгрейда)
```

- По умолчанию скилл ставится в папку `skills/` текущего воркспейса; флаг
  `--global` кладёт его в общий каталог `~/.openclaw/skills`, видимый всем
  локальным агентам.
- **Видимость скиллов** для конкретного агента настраивается в конфиге через
  `agents.defaults.skills` и `agents.list[].skills`.
- **Skill Workshop** — очередь предложений: когда агент замечает переиспользуемую
  работу, он предлагает новый скилл, а вы подтверждаете его перед добавлением.

> 💡 Совет: начинайте с **минимального** набора скиллов под основные задачи и
> добавляйте новые по мере необходимости. Слишком много скиллов = лишний шум, и
> агент начинает применять их не к месту.

## Быстрые команды (шпаргалка)

| Команда | Что делает |
| --- | --- |
| `openclaw --version` | Версия CLI |
| `openclaw doctor` / `openclaw doctor --fix` | Проверка конфигурации / авто-починка |
| `openclaw gateway status` | Статус Gateway (running?) |
| `openclaw gateway restart` | Перезапуск Gateway (применить конфиг) |
| `openclaw status --deep` | Проверка здоровья всех каналов |
| `openclaw logs --follow --local-time` | Лог в реальном времени |
| `openclaw config get` / `set` | Чтение / запись настроек |
| `openclaw models status` | Статус авторизации провайдера |
| `openclaw skills` / `install` / `check` | Список / установка / проверка скиллов |
| `openclaw channels status --probe` | Статус каналов с живой пробой |
| `openclaw pairing list telegram` | Ожидающие коды спаривания Telegram |
| `openclaw pairing approve telegram <КОД>` | Подтвердить спаривание |

## Частые проблемы на Intel Mac

- **`command not found: openclaw` или `node`** — bin-каталог не в `PATH`. На Intel
  Homebrew лежит в `/usr/local`, подключите его и обновите `PATH`:

  ```bash
  eval "$(/usr/local/bin/brew shellenv)"
  echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zshrc
  source ~/.zshrc
  ```

  > На Apple Silicon путь был бы `/opt/homebrew/bin/brew` — на вашем Intel-Mac это
  > именно `/usr/local`.

- **Ошибки библиотеки `sharp`** при установке — переустановите OpenClaw, заставив
  использовать готовые бинарники:

  ```bash
  SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest
  ```

## Полезные ссылки

- [Установка · OpenClaw](https://docs.openclaw.ai/install)
- [Онбординг · OpenClaw](https://docs.openclaw.ai/start/getting-started)
- [Провайдер Anthropic · OpenClaw](https://docs.openclaw.ai/providers/anthropic)
- [Канал Telegram · OpenClaw](https://docs.openclaw.ai/channels/telegram)
- [Скиллы · OpenClaw](https://docs.openclaw.ai/tools/skills)
- [CLI-референс · OpenClaw](https://docs.openclaw.ai/cli)
