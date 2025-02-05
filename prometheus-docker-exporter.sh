#!/bin/bash
set -e

# Install dependencies
apt-get update
apt-get install -y wget curl

# Download docker exporter
wget https://github.com/google/cadvisor/releases/download/v0.47.0/cadvisor -O /usr/local/bin/cadvisor
chmod +x /usr/local/bin/cadvisor

# Create systemd service
cat > /etc/systemd/system/cadvisor.service << EOF
[Unit]
Description=Docker Container Metrics Exporter
Documentation=https://github.com/google/cadvisor
After=docker.service

[Service]
ExecStart=/usr/local/bin/cadvisor \
    --docker_only=true \
    --port=8080 \
    --store_container_labels=false \
    --allow_dynamic_housekeeping=true \
    --housekeeping_interval=10s

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Start service
systemctl daemon-reload
systemctl enable cadvisor
systemctl start cadvisor

# Create prometheus scrape config
cat > /etc/prometheus/conf.d/docker.yml << EOF
- job_name: 'docker'
  static_configs:
    - targets: ['localhost:8080']
  metrics_path: /metrics
EOF

echo "Installation complete. Metrics available at http://localhost:8080/metrics"
