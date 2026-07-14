#!/usr/bin/env python3
"""
OpenClaw Agent Manager — примеры создания, запуска и управления agents.

Установка:
    pip install anthropic python-dotenv

Переменные окружения:
    ANTHROPIC_API_KEY — ваш API key из https://openclaw.anthropic.com
"""

import os
import json
from datetime import datetime
from anthropic import Anthropic

# Инициализируем клиент
client = Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))


def example_1_create_simple_agent():
    """Пример 1: Создать простой агент"""
    print("=" * 60)
    print("Пример 1: Создание простого агента")
    print("=" * 60)

    # Создаём агент через API
    agent = client.agents.create(
        name="simple-reviewer",
        model="claude-opus-4-7-20250219",
        instructions="""
        Ты code reviewer. Смотри на код и даёшь конкретные советы.
        Будь дружелюбен, предлагай улучшения, а не просто критикуй.
        """,
    )

    print(f"✓ Агент создан:")
    print(f"  ID: {agent.id}")
    print(f"  Name: {agent.name}")
    print(f"  Model: {agent.model}")
    print(f"  Created: {agent.created_at}")
    print()

    return agent.id


def example_2_run_task(agent_id: str):
    """Пример 2: Запустить задачу на агенте"""
    print("=" * 60)
    print("Пример 2: Запуск задачи на агенте")
    print("=" * 60)

    # Запускаем агента с input parameters
    task = client.agents.tasks.create(
        agent_id=agent_id,
        input={
            "code_snippet": """
def calculate_sum(arr):
    total = 0
    for i in arr:
        total = total + i
    return total
""",
            "language": "python",
        },
    )

    print(f"✓ Задача запущена:")
    print(f"  Task ID: {task.id}")
    print(f"  Status: {task.status}")
    print(f"  Created: {task.created_at}")
    print()

    # Получаем результат (в production ждите webhook, это sync для примера)
    result = client.agents.tasks.retrieve(agent_id=agent_id, task_id=task.id)
    print(f"Результат задачи:")
    print(f"  Status: {result.status}")
    print(f"  Output: {result.output}")
    print(f"  Tokens used: {result.usage.input_tokens + result.usage.output_tokens}")
    print(f"  Cost: ${result.cost_usd:.4f}")
    print()


def example_3_parallel_tasks(agent_id: str):
    """Пример 3: Запустить несколько задач параллельно"""
    print("=" * 60)
    print("Пример 3: Параллельное выполнение задач")
    print("=" * 60)

    code_samples = [
        {"code": "x = 1\ny = x + 1\nprint(y)", "language": "python"},
        {"code": "const x = 1; const y = x + 1; console.log(y);", "language": "javascript"},
        {
            "code": "public class Adder { public int add(int x) { return x + 1; } }",
            "language": "java",
        },
    ]

    task_ids = []

    # Запускаем все задачи параллельно
    for i, sample in enumerate(code_samples):
        task = client.agents.tasks.create(
            agent_id=agent_id,
            input={
                "code_snippet": sample["code"],
                "language": sample["language"],
                "focus": "readability",
            },
        )
        task_ids.append(task.id)
        print(f"  Запущена задача {i + 1}/{len(code_samples)}: {task.id}")

    print(f"\n✓ Все {len(task_ids)} задач запущены параллельно")
    print()


def example_4_scheduled_agent():
    """Пример 4: Создать агента с расписанием (cron)"""
    print("=" * 60)
    print("Пример 4: Создание scheduled agent")
    print("=" * 60)

    # Создаём агента
    agent = client.agents.create(
        name="nightly-report-generator",
        model="claude-opus-4-7-20250219",
        instructions="""
        Ты аналитик. Каждую ночь:
        1. Собери метрики из логов
        2. Вычисли trends и anomalies
        3. Напиши краткий отчёт
        4. Отправь в Slack канал #daily-reports
        """,
    )

    # Создаём расписание для этого агента
    schedule = client.agents.schedules.create(
        agent_id=agent.id,
        cron="0 2 * * *",  # 2 AM UTC каждый день
        timezone="UTC",
        description="Ежедневный отчёт по метрикам",
    )

    print(f"✓ Агент с расписанием создан:")
    print(f"  Agent ID: {agent.id}")
    print(f"  Schedule ID: {schedule.id}")
    print(f"  Cron: {schedule.cron}")
    print(f"  Next run: {schedule.next_run_at}")
    print()

    return agent.id, schedule.id


def example_5_with_tools(agent_id: str):
    """Пример 5: Агент с подключенными tools (MCP-серверы)"""
    print("=" * 60)
    print("Пример 5: Агент с tools")
    print("=" * 60)

    # Обновляем агента, добавляя tools
    updated_agent = client.agents.update(
        agent_id=agent_id,
        tools=[
            {
                "type": "mcp",
                "name": "github",
                "config": {
                    "server_url": "stdio",  # или HTTP URL если remote MCP
                    "env": {
                        "GITHUB_TOKEN": os.environ.get("GITHUB_TOKEN", ""),
                    },
                },
            },
            {
                "type": "mcp",
                "name": "slack",
                "config": {
                    "server_url": "stdio",
                    "env": {
                        "SLACK_BOT_TOKEN": os.environ.get("SLACK_BOT_TOKEN", ""),
                    },
                },
            },
        ],
    )

    print(f"✓ Агент обновлён с tools:")
    for tool in updated_agent.tools:
        print(f"  - {tool['name']}")
    print()


def example_6_cost_tracking(agent_id: str):
    """Пример 6: Отслеживание стоимости и токенов"""
    print("=" * 60)
    print("Пример 6: Мониторинг затрат")
    print("=" * 60)

    # Списываем список всех задач агента
    tasks = client.agents.tasks.list(agent_id=agent_id, limit=10)

    print(f"Последние 10 задач агента:")
    total_cost = 0
    total_tokens = 0

    for i, task in enumerate(tasks.data, 1):
        tokens = task.usage.input_tokens + task.usage.output_tokens
        cost = task.cost_usd
        total_tokens += tokens
        total_cost += cost

        status_emoji = "✓" if task.status == "completed" else "⚠"
        print(f"  {i}. {status_emoji} {task.id}")
        print(f"     Tokens: {tokens:,} | Cost: ${cost:.4f}")

    print(f"\nИтого за 10 задач:")
    print(f"  Всего токенов: {total_tokens:,}")
    print(f"  Общая стоимость: ${total_cost:.4f}")
    print()


def example_7_error_handling():
    """Пример 7: Обработка ошибок"""
    print("=" * 60)
    print("Пример 7: Error Handling")
    print("=" * 60)

    try:
        # Попробуем получить несуществующего агента
        client.agents.retrieve(agent_id="invalid-id")

    except Exception as e:
        print(f"✓ Перехвачена ошибка (ожидается):")
        print(f"  Тип: {type(e).__name__}")
        print(f"  Сообщение: {str(e)}")
        print()


if __name__ == "__main__":
    print("\n" + "=" * 60)
    print("OpenClaw Agent Manager — примеры")
    print("=" * 60 + "\n")

    # Запускаем примеры
    agent_id = example_1_create_simple_agent()
    example_2_run_task(agent_id)
    example_3_parallel_tasks(agent_id)
    example_4_scheduled_agent()
    # example_5_with_tools(agent_id)  # Раскомментируй если нужны tools
    example_6_cost_tracking(agent_id)
    example_7_error_handling()

    print("=" * 60)
    print("✓ Все примеры выполнены!")
    print("=" * 60)
