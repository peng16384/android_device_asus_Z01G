#!/usr/bin/env bash
# 開啟 CONFIG_AIO —— Android 9 的 adbd 需要它，否則 USB 永遠 offline。
#
# 症狀（_docs/dbg5 的 logcat，adbd 每秒刷上千行）：
#   E adbd: aio: got error submitting read: Function not implemented
#   E adbd: remote usb: read terminated (message): Function not implemented
#   I adbd: closing functionfs transport / registering usb transport   （無限循環）
# host 端就是 `adb devices` 看得到序號但永遠 offline。
#
# 原因：Pie 的 adbd 走 USB_FFS_AIO（io_submit / io_getevents）讀寫端點，
# 而 ASUS 的 defconfig 是 `# CONFIG_AIO is not set`
# （出貨 kernel 的 /proc/config.gz 也一樣 —— 省 7 KB 的最佳化）。
# io_submit 回 ENOSYS，descriptor 寫得進去所以會列舉，但一筆資料都讀不到。
# Oreo 的 adbd 不用 AIO，所以原廠沒事。
#
# 這是第一次真的改 kernel config，所以：
#   - 在 kernel 的 git repo 裡改並 commit，保留可追溯的 patch
#   - 再複製到 AOSP 樹（16_place_trees.sh 是 cp -al 硬連結，
#     sed -i 會斷開連結，所以要明確複製過去）
set -euo pipefail

KSRC="$HOME/zs551kl/kernel/msm-4.4"
KAOSP="$HOME/lineage-16.0/kernel/asus/msm8998"
CFG="arch/arm64/configs/zs551kl-perf_defconfig"

cd "$KSRC"
if grep -q '^CONFIG_AIO=y' "$CFG"; then
    echo "  = 已經開了"
else
    sed -i 's/^# CONFIG_AIO is not set$/CONFIG_AIO=y/' "$CFG"
    grep -q '^CONFIG_AIO=y' "$CFG" || { echo "!!! 取代失敗" >&2; exit 1; }
    echo "  + $CFG: CONFIG_AIO=y"
    git add "$CFG"
    git commit -q -m "zs551kl-perf: 開啟 CONFIG_AIO

Android 9 的 adbd 用 USB_FFS_AIO（io_submit/io_getevents）讀寫 USB 端點。
ASUS 原本是 # CONFIG_AIO is not set，io_submit 回 ENOSYS：
  E adbd: aio: got error submitting read: Function not implemented
gadget 列舉得出來但讀不到資料，host 端永遠停在 offline。
Oreo 的 adbd 不走 AIO，所以原廠不受影響。"
    echo "  + 已在 kernel repo commit"
fi

echo "=== 同步到 AOSP 樹 ==="
cp -f "$KSRC/$CFG" "$KAOSP/$CFG"
grep -n 'CONFIG_AIO' "$KAOSP/$CFG"

echo
echo "=== 順便檢查其他 Pie 會用到、Oreo kernel 可能沒開的選項 ==="
for c in CONFIG_SDCARD_FS CONFIG_QUOTA CONFIG_QFMT_V2 CONFIG_QUOTACTL \
         CONFIG_FUSE_FS CONFIG_CGROUP_SCHEDTUNE CONFIG_MEMCG CONFIG_ANDROID_BINDERFS; do
    printf "  %-28s %s\n" "$c" "$(grep -E "^($c=|# $c is not set)" "$KSRC/$CFG" || echo '（defconfig 沒提到）')"
done
