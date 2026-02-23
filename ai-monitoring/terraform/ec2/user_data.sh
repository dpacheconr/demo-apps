#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/aim-demo-setup.log"
DEMO_DIR="/opt/aim-demo"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== AIM Demo setup - $(date) ==="

# IMDSv2 helper
imds_token() {
  curl -sX PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 300"
}

export DEBIAN_FRONTEND=noninteractive

# -------------------------------------------------------
# 1. Verify pre-installed NVIDIA driver (from DL AMI)
# -------------------------------------------------------
echo "[Setup] NVIDIA driver:"
nvidia-smi

# -------------------------------------------------------
# 2. Install Docker Engine
# -------------------------------------------------------
echo "[Setup] Installing Docker..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg git jq openssl

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
usermod -aG docker ubuntu

# -------------------------------------------------------
# 3. Install NVIDIA Container Toolkit
# -------------------------------------------------------
echo "[Setup] Installing NVIDIA Container Toolkit..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --batch --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update -y
apt-get install -y nvidia-container-toolkit

nvidia-ctk runtime configure --runtime=docker --set-as-default
systemctl restart docker

echo "[Setup] Verifying GPU inside Docker..."
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi

# -------------------------------------------------------
# 4. Install New Relic Infrastructure Agent
# -------------------------------------------------------
echo "[Setup] Installing New Relic Infrastructure Agent..."
curl -fsSL https://download.newrelic.com/infrastructure_agent/gpg/newrelic-infra.gpg \
  | gpg --batch --yes --dearmor -o /usr/share/keyrings/newrelic-infra.gpg

echo "deb [signed-by=/usr/share/keyrings/newrelic-infra.gpg] https://download.newrelic.com/infrastructure_agent/linux/apt/ jammy main" \
  > /etc/apt/sources.list.d/newrelic-infra.list

apt-get update -y
apt-get install -y newrelic-infra

cat > /etc/newrelic-infra.yml <<NRIEOF
license_key: ${new_relic_license_key}
display_name: aim-demo-ec2
NRIEOF

systemctl enable newrelic-infra
systemctl start newrelic-infra

# -------------------------------------------------------
# 5. Clone repo & configure
# -------------------------------------------------------
echo "[Setup] Cloning demo app and configuring..."
git clone https://github.com/newrelic/demo-apps.git "$DEMO_DIR"
cd "$DEMO_DIR/ai-monitoring"

# GPU override — docker compose auto-merges this with the repo's docker-compose.yml
cat > docker-compose.override.yml <<'OVERRIDEEOF'
services:
  ollama-model-a:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
  ollama-model-b:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
OVERRIDEEOF

# Fit CPU/memory limits to g5.xlarge (4 vCPUs, 16 GB RAM)
sed -i "s/cpus: '12.0'/cpus: '2.0'/g; s/cpus: '8.0'/cpus: '1.0'/g" docker-compose.yml
sed -i "s/memory: 8G/memory: 6G/g; s/memory: 12G/memory: 8G/g" docker-compose.yml
sed -i "s/OLLAMA_NUM_THREAD=12/OLLAMA_NUM_THREAD=4/g" docker-compose.yml

# Generate a random Flask secret key
FLASK_SECRET=$(openssl rand -hex 32)

# Write .env
cat > .env <<ENVEOF
OLLAMA_MODEL_A_URL=http://ollama-model-a:11434/v1
OLLAMA_MODEL_B_URL=http://ollama-model-b:11434/v1
MODEL_A_NAME=${model_a_name}
MODEL_B_NAME=${model_b_name}

AGENT_PORT=8001
AGENT_MAX_ITERATIONS=25
AGENT_MAX_EXECUTION_TIME=600
MCP_PORT=8002
LOCUST_WEB_PORT=8089
MCP_SERVER_URL=http://mcp-server:8002
AGENT_URL=http://ai-agent:8001
MCP_URL=http://mcp-server:8002
FLASK_UI_URL=http://flask-ui:8501
AI_AGENT_URL=http://ai-agent:8001

FLASK_SECRET_KEY=$FLASK_SECRET
LOG_LEVEL=INFO

NEW_RELIC_LICENSE_KEY=${new_relic_license_key}
NEW_RELIC_APP_NAME_AI_AGENT=aim-demo_ai-agent
NEW_RELIC_APP_NAME_MCP_SERVER=aim-demo_mcp-server
NEW_RELIC_APP_NAME_FLASK_UI=aim-demo_flask-ui
ENVEOF

# -------------------------------------------------------
# 6. Build & launch
# -------------------------------------------------------
echo "[Setup] Building and starting services..."
docker compose build --no-cache
docker compose up -d

echo "Models loaded:"
docker exec aim-ollama-model-a ollama list
docker exec aim-ollama-model-b ollama list

# -------------------------------------------------------
# 7. Warm up models (pre-load into GPU VRAM)
# -------------------------------------------------------
echo "[Setup] Warming up models to pre-load into GPU memory..."
curl -sf http://localhost:11434/api/generate -d '{"model":"${model_a_name}","prompt":"hi","stream":false}' > /dev/null \
  && echo "[Setup] Model A warmed up" || echo "[Setup] Model A warmup failed"
curl -sf http://localhost:11435/api/generate -d '{"model":"${model_b_name}","prompt":"hi","stream":false}' > /dev/null \
  && echo "[Setup] Model B warmed up" || echo "[Setup] Model B warmup failed"

TOKEN=$(imds_token)
PUBLIC_IP=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4 || echo '<public-ip>')

echo ""
echo "============================================="
echo " AI Monitoring Demo setup complete!"
echo " Access via SSH tunnel (see Terraform outputs)"
echo " Flask UI:  http://localhost:8501"
echo " Locust UI: http://localhost:8089"
echo " Setup log: $LOG_FILE"
echo "============================================="

# -------------------------------------------------------
# 8. Schedule automatic instance termination (TTL)
# -------------------------------------------------------
TTL_HOURS=${instance_ttl_hours}

if [ "$TTL_HOURS" -gt 0 ]; then
  TTL_MINUTES=$((TTL_HOURS * 60))
  echo "[Setup] Instance will auto-terminate in $TTL_HOURS hour(s) ($TTL_MINUTES minutes)"
  echo "[Setup] Scheduled termination at: $(date -d "+$TTL_MINUTES minutes" '+%Y-%m-%d %H:%M:%S %Z')"
  sudo shutdown -h +$TTL_MINUTES "AIM Demo TTL expired ($TTL_HOURS hours). Instance will terminate."
else
  echo "[Setup] Auto-termination DISABLED (instance_ttl_hours=0)"
fi
