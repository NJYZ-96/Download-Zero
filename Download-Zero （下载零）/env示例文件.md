# Download-Zero 配置文件

# === 流量与速度控制 ===
# 24小时内最大总下载量 (GB)
DAILY_LIMIT_GB=150
# 最大下载速度 (例如: 10M, 5M, 500K)
SPEED_LIMIT=10M

# === 随机性控制 ===
# 每个下载循环目标流量的随机范围 (GB)
MIN_LOOP_GB=1
MAX_LOOP_GB=5
# 每个下载循环后休息时间的随机范围 (分钟)
MIN_SLEEP_MINUTES=10
MAX_SLEEP_MINUTES=20

# === 下载源配置 (共9个，用英文逗号分隔) ===
URLS="http://cachefly.cachefly.net/100mb.test,http://speedtest-sgp1.digitalocean.com/1gb.test,http://speed.hetzner.de/1GB.dat,http://ipv4.download.thinkbroadband.com/1GB.zip,http://speedtest.tele2.net/1GB.zip,http://fra.lg.leaseweb.net/1000MB.test,http://mirror.netsite.dk/ubuntu-iso/24.04/ubuntu-24.04-desktop-amd64.iso,https://mirror.vpsfree.cz/centos/8-stream/isos/x86_64/CentOS-Stream-8-x86_64-latest-dvd1.iso,http://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/linux-6.8.9.tar.xz"

# === 故障转移 ===
# 单个下载源连续失败多少次后被禁用
FAIL_THRESHOLD=3

# === 消息推送 ===
# 企业微信 Webhook 地址
WECHAT_WEBHOOK=
