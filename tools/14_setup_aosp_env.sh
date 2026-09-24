#!/usr/bin/env bash
# 安裝 LineageOS 16.0 (Android 9) 的編譯環境
#
# 以 root 執行：
#   wsl -u root -- bash $DEVICE_PATH/tools/14_setup_aosp_env.sh
#
# 重點：
#   - LineageOS 16.0 需要 OpenJDK 8。Ubuntu 20.04 還有（這是當初選 20.04 的主因之一）
#   - 需要一堆 32-bit 相容套件，AOSP 的 prebuilt 工具有些是 32-bit
#   - python2 在 kernel 階段已裝過（CAF kernel 的 gcc-wrapper.py 要用）
# 建置身分與 WSL distro：需要時用環境變數覆蓋
#   BUILD_USER=alice WSL_DISTRO=ubuntu2004 bash tools/xxx.sh
# device tree 根目錄（tools/ 的上一層）；需要時用環境變數覆蓋
DEVICE_PATH="${DEVICE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

BUILD_USER="${BUILD_USER:-${SUDO_USER:-$(id -un)}}"

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== 空間確認 ==="
df -h / /mnt/g | sed 's/^/  /'
echo
echo "  LineageOS 16.0 原始碼約 60–80 GB，編譯產物再約 150 GB。"
echo "  WSL 的 ext4.vhdx 放在 G:，會自動長大。"
echo

echo "=== apt update ==="
apt-get update -qq

echo "=== 安裝套件 ==="
apt-get install -y -qq \
    bc bison build-essential ccache curl flex g++-multilib gcc-multilib git \
    gnupg gperf imagemagick lib32ncurses6 lib32readline-dev lib32z1-dev \
    liblz4-tool libncurses5 libncurses5-dev libsdl1.2-dev libssl-dev \
    libwxgtk3.0-gtk3-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool \
    squashfs-tools xsltproc zip zlib1g-dev \
    openjdk-8-jdk python3 python2 python-is-python2 unzip \
    git-lfs 2>&1 | tail -5

# 一定要 python-is-python2，不能是 python-is-python3。
# AOSP 9 的建置腳本是 Python 2 而且用 #!/usr/bin/env python 呼叫，
# 指到 python3 會在編譯途中爆一堆語法錯誤，且訊息看起來像是 AOSP 自己壞掉：
#   build/make/tools/normalize_path.py:25: print os.path.normpath(p)
#                                                ^ SyntaxError
#   build/make/tools/merge-event-log-tags.py:51: except getopt.GetoptError, err:
#   libcore/annotations/generate_annotated_java_files.py:34: print '...'
# （kernel 的 gcc-wrapper.py 寫的是 env python2，不受影響。
#   本專案 tools/ 底下的腳本一律明確寫 python3。）

# LineageOS 已把 chromium-webview 的 prebuilt APK 搬到 Git LFS。
# 沒裝 git-lfs 的話 repo sync 會在 external/chromium-webview/prebuilt/* 掛掉，
# 而且錯誤訊息是難以聯想的 "Cannot initialize work tree"。
git lfs install --system 2>&1 | sed 's/^/  /' || true
git lfs version | sed 's/^/  /'

echo
echo "=== 切到 Java 8（LineageOS 16.0 需要）==="
update-alternatives --set java  /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java  2>/dev/null || true
update-alternatives --set javac /usr/lib/jvm/java-8-openjdk-amd64/bin/javac     2>/dev/null || true
java -version 2>&1 | sed 's/^/  /'
javac -version 2>&1 | sed 's/^/  /'

echo
echo "=== 安裝 repo ==="
mkdir -p /usr/local/bin
if [ ! -x /usr/local/bin/repo ]; then
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo
    chmod a+rx /usr/local/bin/repo
fi
ls -l /usr/local/bin/repo

echo
echo "=== git 身分（repo init 需要）==="
sudo -u "$BUILD_USER" git config --global user.name  "${GIT_NAME:-Builder}"
sudo -u "$BUILD_USER" git config --global user.email "${GIT_EMAIL:-builder@localhost}"
sudo -u "$BUILD_USER" git config --global color.ui   auto
sudo -u "$BUILD_USER" git config --global --get user.name  | sed 's/^/  name:  /'
sudo -u "$BUILD_USER" git config --global --get user.email | sed 's/^/  email: /'

echo
echo "=== ccache（加速重複編譯）==="
sudo -u "$BUILD_USER" ccache -M 50G 2>&1 | sed 's/^/  /'

echo
echo "環境就緒。接著跑 tools/15_repo_sync.sh（以一般使用者身分，不要用 root）"
