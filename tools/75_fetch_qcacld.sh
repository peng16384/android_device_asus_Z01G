#!/usr/bin/env bash
# 取得 qcacld-3.0（含 qca-wifi-host-cmn 與 fw-api）並放進我們的 kernel 樹。
#
# 為什麼要自己編、不能用原廠的 qca_cld3_wlan.ko：
#   tools/71/72 離線比對過 —— **所有**原廠 .ko 的 modversions CRC 都對不上
#   我們自編的 kernel（qca_cld3_wlan 380 個符號裡 169 個不合，
#   連 br_netfilter 這種小模組都 10 合 26 不合）。
#   代表 ASUS 出貨的 kernel 與他們釋出的 GPL 原始碼不完全一致。
#   關掉 CONFIG_MODULE_SIG_FORCE 也沒用，CRC 那關過不了。
#
# 好消息是平台層已經全通（dmesg）：
#   icnss 18800000.qcom,icnss: Platform driver probed successfully
#   icnss: QMI Server Connected: state: 0x981
#   icnss: WLAN FW is ready: 0xd87
#   -> 這台是 WCN3990 整合式（icnss），不是 PCIe 的 QCA6174。
#      韌體已就緒，只差 qcacld 這顆驅動註冊上去生出 wlan0。
#
# 來源選 LineageOS 的 OnePlus msm8998 kernel：同平台、同 LineageOS 版本，
# 三個目錄已經接好 msm-4.4 的 Kconfig/Makefile，比直接抓 CAF tarball 省事。
set -euo pipefail

SRC_REPO=https://github.com/LineageOS/android_kernel_oneplus_msm8998
BRANCH=lineage-16.0
WORK="$HOME/zs551kl/qcacld_src"
KSRC="$HOME/zs551kl/kernel/msm-4.4"
DIRS="drivers/staging/qcacld-3.0 drivers/staging/qca-wifi-host-cmn drivers/staging/fw-api"

export GIT_TERMINAL_PROMPT=0

# git 2.25.1（Ubuntu 20.04）的 `git clone --sparse` 會失敗：
#     fatal: cannot change to 'https://github.com/...': No such file or directory
#     error: failed to initialize sparse-checkout
# 改用 init + sparse-checkout + fetch，這組在舊版 git 也能用。
if [ ! -d "$WORK/.git" ]; then
    echo "=== 取得原始碼（只抓需要的目錄）==="
    rm -rf "$WORK"
    mkdir -p "$WORK"
    cd "$WORK"
    git init -q
    git remote add origin "$SRC_REPO"
    git config core.sparseCheckout true
    git config extensions.partialClone origin
    for d in $DIRS drivers/staging/Kconfig drivers/staging/Makefile; do
        echo "$d" >> .git/info/sparse-checkout
    done
    git fetch --depth 1 --filter=blob:none origin "$BRANCH"
    git checkout -q FETCH_HEAD
else
    echo "=== 已存在，跳過取得 ==="
    cd "$WORK"
fi

echo
echo "=== 取得的內容 ==="
for d in $DIRS; do
    printf "  %-40s %s 個檔案  %s\n" "$d" \
        "$(find "$WORK/$d" -type f 2>/dev/null | wc -l)" \
        "$(du -sh --si "$WORK/$d" 2>/dev/null | cut -f1)"
done
echo "  HEAD: $(git log -1 --format='%h %ad %s' --date=short)"

echo
echo "=== 它們在 drivers/staging/Kconfig / Makefile 裡是怎麼接的 ==="
grep -n -iE 'qcacld|qca-wifi|fw-api|CLD_LL|QCA_CLD' "$WORK/drivers/staging/Kconfig" "$WORK/drivers/staging/Makefile" 2>/dev/null

echo
echo "=== 我們 kernel 樹裡對應位置目前的狀況 ==="
for d in $DIRS; do
    printf "  %-40s %s\n" "$d" "$([ -d "$KSRC/$d" ] && echo '已存在' || echo '（沒有）')"
done
grep -n -iE 'qcacld|qca-wifi|fw-api' "$KSRC/drivers/staging/Kconfig" "$KSRC/drivers/staging/Makefile" 2>/dev/null || echo "  我們的 staging Kconfig/Makefile 沒有提到（預期）"
