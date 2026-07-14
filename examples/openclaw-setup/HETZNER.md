# OpenClaw на Hetzner Cloud — Complete Deployment Guide

Полная инструкция по развёртыванию OpenClaw агентов на Hetzner: от регистрации до production-ready setup с мониторингом и автоскейлингом.

## Why Hetzner?

| Параметр | Hetzner | AWS | DigitalOcean |
|---|---|---|---|
| Цена (2 vCPU, 4GB) | €5/месяц | $25/месяц | $12/месяц |
| Datacenters | 5 (EU, US) | 33 | 12 |
| Outbound traffic | Unlimited | $0.09/GB | $0.01/GB |
| Setup time | 1 минута | 10+ минут | 5 минут |
| Идеален для | EU-based agents | Global scale | Small projects |

**Вывод:** Hetzner — лучший выбор для European-based автоматизации и фоновых агентов.

---

## Setup A: Быстрый старт (5 минут)

### 1. Регистрация на Hetzner Cloud

```bash
# 1. Идёшь на https://console.hetzner.cloud
# 2. Регистрируешься (требует credit card)
# 3. Создаёшь новый project: "OpenClaw"
# 4. Генерируешь API token: API Tokens → Generate new token
```

### 2. Установка Terraform

```bash
# macOS
brew install terraform

# Linux
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
mv terraform /usr/local/bin/
```

### 3. Deploy сервера (один коммит!)

```bash
# 1. Скопируй файлы из examples/openclaw-setup/
cp terraform.hetzner.tf user-data.sh .

# 2. Запусти Terraform
export HCLOUD_TOKEN="your-api-token-here"
terraform init
terraform apply -var 'api_key=sk-ant-...'

# 3. Жди 1 минуту — сервер готов
terraform output ssh_command
# Output: ssh root@<floating-ip>
```

**Готово!** Агент работает.

### 4. Проверка статуса

```bash
# SSH на сервер
ssh root@<floating-ip>

# Смотрим логи
tail -f /mnt/openclaw-logs/openclaw.log

# Проверяем supervisor
supervisorctl status
```

---

## Setup B: Docker вариант

Если хочешь контейнер вместо bare metal:

```bash
# 1. Собираешь Docker image
docker build -f Dockerfile.hetzner -t openclaw:latest .

# 2. Загружаешь в registry (Hetzner или Docker Hub)
docker tag openclaw:latest registry.hetzner.cloud/openclaw:latest
docker push registry.hetzner.cloud/openclaw:latest

# 3. Обновляешь user-data.sh для запуска контейнера
# Вместо supervisor → docker run в systemd service
```

---

## Setup C: Масштабирование (10+ параллельных агентов)

Для 100+ одновременных задач используй Load Balancer:

```hcl
# Terraform: создание 3 серверов за load balancer
resource "hcloud_load_balancer" "openclaw" {
  name               = "openclaw-lb"
  load_balancer_type = "lb11"
  location           = "nbg1"
}

resource "hcloud_server" "openclaw_pool" {
  count       = 3
  name        = "openclaw-agent-${count.index + 1}"
  server_type = "cpx21"
  # ... остальное как в terraform.hetzner.tf
}

resource "hcloud_load_balancer_target" "openclaw_pool" {
  count            = 3
  load_balancer_id = hcloud_load_balancer.openclaw.id
  type             = "server"
  server_id        = hcloud_server.openclaw_pool[count.index].id
}
```

Cost: 3× €10 (CPX21) + €5 (LB) = **€35/месяц** за 50+ parallel tasks.

---

## Best Practices

### 1. Security

```bash
# Ограничи SSH только по IP
resource "hcloud_firewall" "openclaw" {
  rule {
    direction   = "in"
    protocol    = "tcp"
    source_ips  = ["203.0.113.42/32"]  # Твой IP
    destination_port = "22"
  }
}

# Используй SSH keys, не passwords
# В production: используй Vault для API keys, не .env файлы
```

### 2. Мониторинг

```bash
# Prometheus node exporter установлен автоматически (user-data.sh)
# Метрики доступны на :9100/metrics

# Подключи к Prometheus:
# scrape_configs:
#   - job_name: 'openclaw'
#     static_configs:
#       - targets: ['<floating-ip>:9100']
```

### 3. Backup

```bash
# Cron job автоматически ежедневно бэкапит конфиги
# Хранятся в /mnt/openclaw-logs/backup-*.tar.gz
# Скопируй в Hetzner Backups для долгосрочного хранения

# Manual backup:
tar -czf openclaw-backup-$(date +%Y%m%d).tar.gz /opt/openclaw/
```

### 4. Cost Optimization

| Optimizaton | Savings | Trade-off |
|---|---|---|
| Spot instances | ❌ Не поддерживаются Hetzner | — |
| Reserved capacity | ❌ Нет долгосрочных контрактов | — |
| Оптимизация CPU | 10–20% | Меньше параллельности |
| Off-peak scheduling | 30–50% | Гибкость времени запуска |
| Reserved bandwidth | 0% | Unlimited бесплатно |

**Рекомендация:** Запускай тяжёлые задачи ночью (когда дешевле в других сервисах), гибкие — днём.

---

## Troubleshooting

### Issue: Агент не запускается

```bash
# SSH на сервер
ssh root@<ip>

# Проверь supervisor
supervisorctl status

# Если stopped — смотри логи
tail -100 /mnt/openclaw-logs/openclaw.log

# Перезагрузи
supervisorctl restart openclaw
```

### Issue: "Permission denied" на /mnt/openclaw-logs

```bash
# Volume не смонтирован правильно
ls -la /mnt/openclaw-logs

# Ручное монтирование
lsblk  # Найди device
mount /dev/sda /mnt/openclaw-logs
chown -R openclaw:openclaw /mnt/openclaw-logs
```

### Issue: High CPU usage

```bash
# Смотри какой процесс жрёт
top -u openclaw

# Если agent-manager.py — проверь instructions
# Возможно, loop бесконечный или слишком много подзадач
```

### Issue: Out of disk space

```bash
# Проверь использование
df -h

# Очисти старые логи
find /mnt/openclaw-logs -name "*.log" -mtime +30 -delete

# Увеличь Volume
hcloud volume resize <volume-id> <new-size>
```

---

## Advanced: Kubernetes на Hetzner

Для очень больших установок (500+ parallel agents):

```bash
# 1. Создай Kubernetes cluster через Terraform
# https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/hcloud_server

# 2. Deploy OpenClaw:
# - StatefulSet для агентов
# - CronJob для scheduled tasks
# - HorizontalPodAutoscaler для auto-scaling

# 3. Persistent storage: Hetzner Volumes + HCloud CSI driver
```

**Cost:** ~€100/месяц за 20 узлов, 500+ parallel agents.

---

## Migration: Hetzner → Production

Когда setup работает и прибыльный:

1. **Backup configuration:** `tar -czf openclaw-prod.tar.gz /opt/openclaw/`
2. **Move to enterprise:** OpenClaw Enterprise на Amazon/GCP
3. **Hetzner remains:** EU backup agent, failover scenarios
4. **Redundancy:** Multi-region (Hetzner EU + cloud EU)

---

## References

- [Hetzner Cloud Console](https://console.hetzner.cloud)
- [Hetzner Cloud API Docs](https://docs.hetzner.cloud/)
- [Terraform Hetzner Provider](https://registry.terraform.io/providers/hetznercloud/hcloud/)
- [supervisor Documentation](http://supervisord.org/)
- [OpenClaw on Hetzner: Community Tips](https://github.com/anthropics/anthropic-cookbook/discussions/hetzner)
