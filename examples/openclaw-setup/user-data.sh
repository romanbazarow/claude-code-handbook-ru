#!/bin/bash
# User data script для инициализации OpenClaw агента на Hetzner Cloud
# Автоматически запускается при создании сервера через Terraform

set -e

echo "=== OpenClaw Agent Initialization on Hetzner ==="

# Обновляем систему
apt-get update
apt-get upgrade -y
apt-get install -y \
    python3-pip \
    python3-venv \
    git \
    curl \
    jq \
    supervisor \
    ca-certificates \
    htop \
    net-tools

echo "✓ System packages installed"

# Создаём пользователя для агента
useradd -m -s /bin/bash openclaw || true
mkdir -p /opt/openclaw
chown -R openclaw:openclaw /opt/openclaw

echo "✓ User and directories created"

# Монтируем Volume (если подключен)
if [ -b /dev/disk/by-id/scsi-0HC*_volume-* ]; then
    VOLUME_PATH=$(ls /dev/disk/by-id/scsi-0HC*_volume-* | head -1)
    mkdir -p /mnt/openclaw-logs
    mount "$VOLUME_PATH" /mnt/openclaw-logs
    chown -R openclaw:openclaw /mnt/openclaw-logs
    echo "✓ Volume mounted at /mnt/openclaw-logs"
fi

# Python virtual environment
cd /opt/openclaw
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install anthropic python-dotenv requests

echo "✓ Python environment ready"

# Создаём .env файл с API key
cat > .env <<EOF
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"
AGENT_NAME="${AGENT_NAME}"
LOG_DIR="/mnt/openclaw-logs"
LOG_LEVEL="INFO"
EOF

chmod 600 .env
chown openclaw:openclaw .env

echo "✓ Environment configured"

# Скопируем примеры (если есть)
if [ -d "/root/openclaw-setup" ]; then
    cp /root/openclaw-setup/* /opt/openclaw/ || true
    chown -R openclaw:openclaw /opt/openclaw
fi

# Supervisor конфиг для управления агентом
cat > /etc/supervisor/conf.d/openclaw.conf <<EOF
[program:openclaw]
command=/opt/openclaw/venv/bin/python /opt/openclaw/agent-runner.py
directory=/opt/openclaw
user=openclaw
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/mnt/openclaw-logs/openclaw.log
environment=PYTHONUNBUFFERED=1

[program:openclaw-monitor]
command=/opt/openclaw/venv/bin/python -u /opt/openclaw/monitor.py
directory=/opt/openclaw
user=openclaw
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/mnt/openclaw-logs/monitor.log
environment=PYTHONUNBUFFERED=1
EOF

systemctl restart supervisor
supervisorctl reread
supervisorctl update

echo "✓ Supervisor configured"

# Cron для регулярных задач (опционально)
cat > /home/openclaw/crontab <<'CRON'
# Проверка статуса каждые 5 минут
*/5 * * * * /opt/openclaw/venv/bin/python /opt/openclaw/health-check.py >> /mnt/openclaw-logs/cron.log 2>&1

# Запуск daily aggregator в 02:00 UTC
0 2 * * * /opt/openclaw/venv/bin/python /opt/openclaw/daily-report.py >> /mnt/openclaw-logs/cron.log 2>&1

# Очистка логов старше 30 дней
0 3 * * * find /mnt/openclaw-logs -name "*.log" -mtime +30 -delete

# Backup конфиги в 04:00 UTC
0 4 * * * tar -czf /mnt/openclaw-logs/backup-$(date +\%Y\%m\%d).tar.gz /opt/openclaw/ 2>&1 | head -20
CRON

crontab -u openclaw /home/openclaw/crontab

echo "✓ Cron jobs configured"

# Мониторинг (опционально)
apt-get install -y prometheus-node-exporter
systemctl enable prometheus-node-exporter
systemctl start prometheus-node-exporter

echo "✓ Monitoring enabled"

# Финальная проверка
sleep 3
supervisorctl status

echo ""
echo "=== ✓ OpenClaw Agent Ready on Hetzner ==="
echo ""
echo "Access logs:"
echo "  tail -f /mnt/openclaw-logs/openclaw.log"
echo ""
echo "Check status:"
echo "  supervisorctl status"
echo ""
echo "View metrics:"
echo "  curl http://localhost:9100/metrics"
echo ""
