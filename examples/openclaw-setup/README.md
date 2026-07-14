# OpenClaw Setup — примеры и шаблоны

Полные примеры создания и управления OpenClaw agents для автоматизации разработки и CI/CD-задач.

## Структура

- **agent-config.yaml** — Декларативное описание агента (YAML). Используется для сохранения конфигурации в версионный контроль.
- **agent-manager.py** — Примеры SDK-использования (Python). 7 сценариев: создание, запуск, параллелизм, расписание, tools, мониторинг.
- **README.md** — Этот файл.

## Быстрый старт

### 1. Установка SDK

```bash
pip install anthropic python-dotenv
```

### 2. API-ключ

```bash
# Получи key из https://openclaw.anthropic.com → API Keys
export ANTHROPIC_API_KEY="sk-ant-..."
```

### 3. Запуск примеров

```bash
python agent-manager.py
```

Выведет 7 примеров:
1. Создание простого агента
2. Запуск одной задачи
3. Параллельное выполнение (3 задачи сразу)
4. Расписание (cron) для агента
5. Подключение tools (GitHub, Slack)
6. Отслеживание стоимости и токенов
7. Обработка ошибок

## Кейсы использования

### Кейс A: Автоматический Code Review ночью

```bash
# 1. Создаёшь агента с instructions про code-review
# 2. Подключаешь GitHub MCP-сервер
# 3. Ставишь расписание (cron "0 23 * * *" = 23:00 UTC)
# 4. Агент автоматически в 23:00 читает все открытые PR'ы, 
#    делает ревью, комментирует и добавляет labels
```

Файл: `agent-config.yaml` в этой папке — готовый пример.

### Кейс B: Параллельная обработка 1000 issues

```bash
# 1. У тебя 1000 issues в GitHub
# 2. Создаёшь агента с instructions про classification
# 3. Запускаешь 1000 задач параллельно (каждая обрабатывает 1 issue)
# 4. Агент автоматически:
#    - читает issue description
#    - присваивает label (feature/bug/documentation/question)
#    - ставит priority (high/medium/low)
#    - комментирует if needed
# 5. Результат: 1000 issues в 2 минуты вместо недели ручной работы
```

Код: пример 3 в `agent-manager.py`.

### Кейс C: 24/7 Security Auditor

```bash
# 1. Каждый час агент сканирует dependencies
# 2. Ищет known vulnerabilities
# 3. Если нашёл: открывает issue / коммитит patch / отправляет alert в Slack
# 4. Всё автоматически, без вашего участия
```

### Кейс D: Multi-Model Review (Claude + Codex)

```bash
# OpenClaw поддерживает несколько model параллельно
# Запускаешь code-review и в Claude, и в GPT-4 одновременно
# Сравниваешь их мнения, берёшь лучшее (majority vote)
```

## Архитектура

```
┌─────────────────────────────────────┐
│    OpenClaw Console                 │
│  - UI для создания agents           │
│  - Мониторинг задач                 │
│  - Бюджеты и ограничения            │
└────────────┬────────────────────────┘
             │
    ┌────────┴────────┐
    │                 │
┌───▼─────────┐  ┌────▼─────────────┐
│ API + SDK   │  │ Webhooks         │
│ (HTTP/gRPC) │  │ (task completion)│
└───┬─────────┘  └────┬─────────────┘
    │                 │
    └────┬────────────┘
         │
    ┌────▼────────────────────────┐
    │  OpenClaw Runtime           │
    │ - Agent execution           │
    │ - Task scheduling           │
    │ - MCP tool bridging         │
    │ - Budget enforcement        │
    └────┬─────────────────────────┘
         │
    ┌────▼──────────────────────────┐
    │  Claude Opus 4.7 / Sonnet     │
    │  (managed inference)          │
    └────┬──────────────────────────┘
         │
    ┌────▼──────────────┐
    │ MCP Tools         │
    │ - GitHub          │
    │ - Slack           │
    │ - Databases       │
    │ - Custom APIs     │
    └───────────────────┘
```

## Варианты деплоя

### Вариант 1: Standalone agents

Каждый агент запускается отдельно через `client.agents.tasks.create()`. Простейший вариант.

```python
response = client.agents.tasks.create(
    agent_id="agent-123",
    input={"issue_id": "456"},
)
```

### Вариант 2: Scheduled / Cron

Агент запускается по расписанию автоматически.

```python
schedule = client.agents.schedules.create(
    agent_id="agent-123",
    cron="0 23 * * *",  # Every day at 23:00 UTC
)
```

### Вариант 3: REST API (no-code)

Если у вас нет SDK, можно управлять агентами через REST API:

```bash
curl -X POST https://api.anthropic.com/v1/agents/tasks \
  -H "Authorization: Bearer sk-ant-..." \
  -d '{
    "agent_id": "agent-123",
    "input": {"code": "..."}
  }'
```

### Вариант 4: Webhooks + External Trigger

Внешняя система (GitHub Actions, Jenkins, etc.) запускает агента через webhook.

```python
# GitHub Actions → OpenClaw webhook → agent task created
```

## Ограничения и best practices

| Ограничение | Значение | Хак |
|---|---|---|
| Max context size | 100K (Pro) / 200K+ (Ent) | Splitting на subagents |
| Max concurrent tasks per agent | 10 | Multiple agent copies |
| Max task duration | 1 hour | Break into subtasks |
| Rate limit | 100 req/min | Batch operations |
| Cost | $0.50–$3.00 per task | Budget limits per agent |

**Best practices:**

1. **Budget limits** — Всегда ставь `max_tokens` и `max_cost_usd` на агента
2. **Parallel, not sequential** — 10 parallel tasks за 2 минуты > 10 sequential за час
3. **Stateless tasks** — Каждая задача =独立 (независимая), no shared state between tasks
4. **Webhooks over polling** — Дождись callback, не проверяй статус в цикле
5. **MCP tools selectively** — Не подключай 20 tools сразу; только нужные 3–5

## Интеграция с Claude Code

Часто разрабатывают локально в Claude Code, запускают в production в OpenClaw:

```
┌─────────────────────────────────────┐
│      Development (Claude Code)      │
│  - Iterate on agent instructions    │
│  - Test locally                     │
│  - Debug with full IDE              │
└─────────────────────────────────────┘
           │
           │ (copy instructions)
           ▼
┌─────────────────────────────────────┐
│   Production (OpenClaw)             │
│  - Deploy agent config              │
│  - Set cron / webhooks              │
│  - Monitor 24/7                     │
│  - Auto-scale parallel              │
└─────────────────────────────────────┘
```

## Ресурсы

- [OpenClaw Official Docs](https://docs.anthropic.com/en/docs/openclaw)
- [Anthropic Cookbook](https://github.com/anthropics/anthropic-cookbook)
- [awesome-openclaw-skills](https://sky-lv.github.io/awesome-openclaw-skills)
