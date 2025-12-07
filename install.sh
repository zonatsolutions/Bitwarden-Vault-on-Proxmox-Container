#!/bin/bash
set -e

##########################################
# BITWARDEN INSTALL SCRIPT BY TALHA ALI
# For Proxmox LXC Containers
# www.zonatsolutions.com
##########################################

MIN_CPU_GHZ=1.4
MIN_RAM_MB=2000
MIN_STORAGE_MB=12000
BITWARDEN_USER="bitwarden"
BITWARDEN_DIR="/opt/bitwarden"

echo "=============================================="
echo " Bitwarden Self-Hosted Install Script"
echo "=============================================="
echo ""

### Function to convert MHz → GHz ###
mhz_to_ghz() {
awk -v mhz="$1" 'BEGIN { printf "%.2f", mhz / 1000 }'
}

### Check architecture ###
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
echo "❌ ERROR: Bitwarden requires x86_64 architecture. Detected: $ARCH"
exit 1
fi

### Check CPU speed ###
CPU_MHZ=$(lscpu | awk '/CPU MHz/ {print $3; exit}')

# If CPU MHz is missing (common in Proxmox LXC), default to safe high value
if [[ -z "$CPU_MHZ" ]]; then
echo "⚠ CPU MHz not reported by LXC, assuming CPU meets requirement"
CPU_GHZ=2.5
else
CPU_GHZ=$(mhz_to_ghz "$CPU_MHZ")
fi

if (( $(echo "$CPU_GHZ < $MIN_CPU_GHZ" | bc -l) )); then
echo "❌ CPU speed too low. Detected: ${CPU_GHZ}GHz"
echo "Minimum required: ${MIN_CPU_GHZ}GHz"
exit 1
fi

### Check RAM ###
RAM_MB=$(grep MemTotal /proc/meminfo | awk '{print $2/1024}')

if (( $(echo "$RAM_MB < $MIN_RAM_MB" | bc -l) )); then
echo "❌ RAM too low. Detected: ${RAM_MB}MB"
echo "Minimum required: ${MIN_RAM_MB}MB"
exit 1
fi

### Check Storage ###
ROOT_FS_MB=$(df / | tail -1 | awk '{print $4/1024}')

if (( $(echo "$ROOT_FS_MB < $MIN_STORAGE_MB" | bc -l) )); then
echo "❌ Not enough storage. Available: ${ROOT_FS_MB}MB"
echo "Minimum required: ${MIN_STORAGE_MB}MB"
exit 1
fi

echo "✅ System requirements met."
echo ""

### Update system ###
echo "=== Updating & upgrading system ==="
apt update && apt upgrade -y

### Install dependencies ###
echo "=== Installing required packages ==="
apt install -y curl ca-certificates gnupg lsb-release apt-transport-https software-properties-common bc

#############################################
# Install Docker (LXC-safe method)
#############################################

echo "=== Installing Docker GPG key (LXC-compatible) ==="

# Clean old keys
rm -f /etc/apt/keyrings/docker.gpg
mkdir -p /etc/apt/keyrings || true

# Try modern method
if curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
echo "✓ Docker key installed (keyring method)"
else
echo "⚠ Keyring method failed — using fallback apt-key (safe for LXC)"
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 7EA0A9C3F273FCD8
fi

chmod a+r /etc/apt/keyrings/docker.gpg 2>/dev/null || true

echo "=== Adding Docker repository ==="

CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")

cat <<EOF | tee /etc/apt/sources.list.d/docker.list
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $CODENAME stable
EOF

apt update || {
echo "⚠ Repo signature verification failed — enabling fallback insecure mode"
echo "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/debian $CODENAME stable" > /etc/apt/sources.list.d/docker.list
apt update
}

echo "=== Installing Docker ==="
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

echo "=== Docker installed successfully ==="
echo ""

#############################################
# Create Bitwarden User + Directory
#############################################

echo "=== Creating bitwarden user ==="
if ! id "$BITWARDEN_USER" >/dev/null 2>&1; then
useradd -m -s /bin/bash "$BITWARDEN_USER"
fi

usermod -aG docker "$BITWARDEN_USER"

echo "=== Creating Bitwarden directory ==="
mkdir -p "$BITWARDEN_DIR"
chown $BITWARDEN_USER:$BITWARDEN_USER "$BITWARDEN_DIR"
chmod 700 "$BITWARDEN_DIR"

cd "$BITWARDEN_DIR"

echo "=== Downloading Bitwarden installer ==="
runuser -u "$BITWARDEN_USER" -- bash -c \
"curl -Lso bitwarden.sh 'https://func.bitwarden.com/api/dl/?app=self-host&platform=linux' && chmod 700 bitwarden.sh"

echo "=== Running Bitwarden installer ==="
#runuser -u "$BITWARDEN_USER" -- bash -c "./bitwarden.sh install"

echo -e "\e[1;37;42m Script by Talha Ali (Zonat Solutions) \e[0m "
echo -e "\e[1;30;47m Support My Efforts by Subscribing my YouTube \e[0m"
echo -e "\e[1;30;47m Channel and like the Videos :) Thank you \e[0m"
echo -e "\e[1;31;47m or buy me coffee: donate.zonatsolutions.com \e[0m"

sleep 5

echo ""
echo "=============================================="
echo " Bitwarden installation complete!"
echo " To start Bitwarden:"
echo " change user by command : su bitwarden"
echo " cd /opt/bitwarden && ./bitwarden.sh install"
echo "=============================================="
