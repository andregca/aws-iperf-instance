#!/bin/bash
# ---------- Amazon Linux 2023 user‑data for an iperf3 server ----------
set -euo pipefail
exec > /var/log/user-data.log 2>&1   # handy for troubleshooting

# 1. Install prerequisites
dnf -y update
dnf -y install iperf3 logrotate              # iperf3 is in the AL2023 repos 

# 2. Prepare log file
install -m 644 -o root -g root /dev/null /var/log/iperf3-server.log

# 3. Create systemd service unit
cat >/etc/systemd/system/iperf3.service <<'EOF'
[Unit]
Description=iperf3 bandwidth‑test server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
Group=nobody
# Run in server (listen) mode; let systemd keep the process in the foreground
ExecStart=/usr/bin/iperf3 -s
Restart=on-failure
# Log everything to a single file (systemd ≥ 236 supports append:) :contentReference[oaicite:1]{index=1}
StandardOutput=append:/var/log/iperf3-server.log
StandardError=append:/var/log/iperf3-server.log

[Install]
WantedBy=multi-user.target
EOF

# 4. Configure logrotate
cat >/etc/logrotate.d/iperf3 <<'EOF'
/var/log/iperf3-server.log {
    size 1M          # rotate when the file grows beyond 1 MiB
    rotate 5         # keep five old logs
    compress         # gzip the rotated logs
    copytruncate     # truncate in‑place so iperf3 keeps logging
    missingok
    notifempty
}
EOF
# logrotate runs daily by default on AL2023; the size directive makes rotation size‑based :contentReference[oaicite:2]{index=2}

# 5. Enable and start the service
systemctl daemon-reload
systemctl enable --now iperf3.service
echo "iperf3 server installed and running."

# ---------------------------------------------------------------------

