#!/usr/bin/env bash
#
# 設定 LineageOS 22.2 的建置環境：WSL distro「lineage22」
#
#   wsl -d lineage22 -u root env BUILD_USER=<名字> bash tools/120_setup_lineage22_wsl.sh   # 在這個 repo 的 clone 裡
#
# ## 為什麼另開一個 distro
#
# - 16.0 的 distro（ubuntu2004）要 python -> python2；22.2 要 python -> python3。
#   同一個環境裡只能擇一，全域切換一定會弄壞其中一邊。
# - 22.2 官方建議 400 GB 磁碟空間。
#
# 建立方式（Windows 端，2026-09-25）：
#   wsl --import lineage22 <放 vhdx 的目錄> <下載的 focal-server-cloudimg-amd64-root.tar.xz> --version 2
#   （先對過 rootfs 的 sha256：cloud-images.ubuntu.com 同目錄的 SHA256SUMS）
# 記憶體：%USERPROFILE%\.wslconfig 的 memory 從 32GB 改成 64GB（lineage-21 以上官方要 64 GB）。
#
# 套件照 LineageOS wiki 的 device_build_before_init（Ubuntu 20.04 是官方唯一測過的版本）。
set -e -o pipefail
[ "$(id -u)" = 0 ] || { echo "要用 root 跑（wsl -d lineage22 -u root env BUILD_USER=<名字> bash ...）" >&2; exit 1; }

U=${BUILD_USER:?"要建立的一般使用者名稱：BUILD_USER=<名字>"}
echo "=== 使用者 $U ==="
if ! id $U >/dev/null 2>&1; then
    useradd -m -u 1000 -s /bin/bash -G sudo $U
    passwd -l $U >/dev/null
fi
echo "$U ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-$U
chmod 440 /etc/sudoers.d/90-$U

echo "=== /etc/wsl.conf ==="
cat > /etc/wsl.conf <<EOF
[user]
default=$U
[boot]
systemd=false
[interop]
appendWindowsPath=false
EOF

echo "=== apt ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q \
    bc bison build-essential ccache curl flex g++-multilib gcc-multilib git git-lfs \
    gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev liblz4-tool \
    lib32ncurses5-dev libncurses5 libncurses5-dev libsdl1.2-dev libssl-dev \
    libxml2 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools xsltproc \
    zip unzip zlib1g-dev python3 python-is-python3 cpio kmod device-tree-compiler \
    erofs-utils openssl xz-utils ca-certificates locales
locale-gen en_US.UTF-8 >/dev/null

echo "=== repo ==="
if [ ! -x /usr/local/bin/repo ]; then
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo
    chmod a+rx /usr/local/bin/repo
fi

# cd 到家目錄：從 Windows 磁碟上的 checkout 執行時，git lfs install 會以為要裝進那個 repo（踩過）
sudo -u $U -H bash -c 'cd ~ && git lfs install --skip-repo >/dev/null &&
    git config --global user.name  "android-build" &&
    git config --global user.email "android-build@localhost" &&
    git config --global color.ui false && git config --global --list'

echo "=== 結果 ==="
python --version; git --version; git lfs version; repo --version 2>/dev/null | head -2 || true
free -g | head -2; df -h / | tail -1; nproc
