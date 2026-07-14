# Terraform: Deploy OpenClaw агента на Hetzner Cloud
#
# Использование:
#   terraform init
#   terraform plan
#   terraform apply
#
# Требует:
#   - Hetzner Cloud API token в HCLOUD_TOKEN env var
#   - SSH public key в ~/.ssh/id_rsa.pub

terraform {
  required_version = ">= 1.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.40"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "server_type" {
  description = "Hetzner server type"
  type        = string
  default     = "cpx11"  # 2 vCPU, 4GB RAM, €5/month
}

variable "location" {
  description = "Hetzner datacenter location"
  type        = string
  default     = "nbg1"  # Nuremberg, Germany
}

variable "agent_name" {
  description = "OpenClaw agent name"
  type        = string
  default     = "openclaw-agent-1"
}

variable "api_key" {
  description = "Anthropic API key"
  type        = string
  sensitive   = true
}

# SSH ключ для доступа
resource "hcloud_ssh_key" "openclaw" {
  name       = "openclaw-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

# Firewall — разрешаем только необходимое
resource "hcloud_firewall" "openclaw" {
  name = "openclaw-fw"

  # Входящий трафик: ограничиваем
  rule {
    direction = "in"
    source_ips = [
      "0.0.0.0/0"     # SSH (измени на свой IP в production!)
    ]
    destination_port = "22"
    protocol         = "tcp"
  }

  # Исходящий трафик: разрешаем все (нужен для API)
  rule {
    direction = "out"
    destination_ips = [
      "0.0.0.0/0"
    ]
    protocol = "tcp"
  }

  rule {
    direction = "out"
    destination_ips = [
      "0.0.0.0/0"
    ]
    protocol = "udp"
  }
}

# Hetzner Volume для логов (опционально, но рекомендуется)
resource "hcloud_volume" "openclaw_logs" {
  name              = "openclaw-logs"
  size              = 10  # 10 GB
  location          = var.location
  automount         = false
  format            = "ext4"
  delete_protection = false

  labels = {
    app = "openclaw"
  }
}

# Сам сервер
resource "hcloud_server" "openclaw" {
  name        = var.agent_name
  image       = "ubuntu-22.04"
  server_type = var.server_type
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.openclaw.id]
  firewall_ids = [hcloud_firewall.openclaw.id]

  # User data script — установка всего необходимого
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    ANTHROPIC_API_KEY = var.api_key
    AGENT_NAME        = var.agent_name
  }))

  labels = {
    app         = "openclaw"
    environment = "production"
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Подключаем Volume к серверу
resource "hcloud_volume_attachment" "openclaw_logs" {
  volume_id = hcloud_volume.openclaw_logs.id
  server_id = hcloud_server.openclaw.id
  automount = true
}

# Floating IP для стабильного адреса
resource "hcloud_floating_ip" "openclaw" {
  type            = "ipv4"
  location        = var.location
  description     = "OpenClaw agent floating IP"
  delete_protection = false

  labels = {
    app = "openclaw"
  }
}

resource "hcloud_floating_ip_assignment" "openclaw" {
  floating_ip_id = hcloud_floating_ip.openclaw.id
  server_id      = hcloud_server.openclaw.id
}

# Outputs
output "server_ip" {
  description = "Hetzner server IP address"
  value       = hcloud_server.openclaw.ipv4_address
}

output "floating_ip" {
  description = "Floating IP for stable access"
  value       = hcloud_floating_ip.openclaw.ip_address
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh root@${hcloud_floating_ip.openclaw.ip_address}"
}

output "monthly_cost_usd" {
  description = "Approximate monthly cost"
  value       = var.server_type == "cpx11" ? "$5.83" : var.server_type == "cpx21" ? "$11.66" : "$23.33"
}
