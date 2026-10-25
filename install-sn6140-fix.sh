#!/bin/bash
# 安装 SN6140 扬声器永久修复（看护进程 + 休眠恢复钩子）
# 用法: sudo bash install-sn6140-fix.sh
set -e
cd "$(dirname "$0")"

install -m 755 sn6140-watchdog.sh /usr/local/sbin/sn6140-watchdog
install -m 644 sn6140-watchdog.service /etc/systemd/system/sn6140-watchdog.service

# 休眠恢复钩子：恢复后立即注入一次（平时由看护进程兜底）
cat > /usr/lib/systemd/system-sleep/sn6140-watchdog <<'EOF'
#!/bin/sh
case "$1/$2" in
  post/*) /usr/local/sbin/sn6140-watchdog --once ;;
esac
EOF
chmod 755 /usr/lib/systemd/system-sleep/sn6140-watchdog

systemctl daemon-reload
systemctl enable --now sn6140-watchdog.service

echo "==> 安装完成。看护进程已启动，3 秒内应生效。"
