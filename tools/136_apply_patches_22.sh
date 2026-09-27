#!/usr/bin/env bash
#
# 22.2：把 patches/<專案路徑>/*.patch 套到原始碼樹（在 lineage22 distro 內）
#
#   bash device/asus/Z01G/tools/136_apply_patches_22.sh
#
# 可重跑：已套過的（git apply --reverse --check 成立）跳過；兩個方向都套不上就停。
# 只改工作樹、不 commit（repo sync 前要先 git -C <專案> checkout -- . 或 stash，否則 sync 會拒絕）。
#
# 目前的 patch：
#   build/make           0001  fs_config_files_system 不再略過 vendor/ 條目：沒有 vendor 分割區時，vendor 那份
#                              要到 $(PRODUCT_OUT)/vendor/etc/ 找、永遠不存在 -> config.fs 的 capabilities 全沒進
#                              system.img（pm-service 無限重試 bind、吃滿一顆核心）。
#                              （先試過在 device tree 另做一份 + overrides：Soong 對每個模組都產生安裝規則，
#                               同一路徑兩個模組 -> kati "overriding commands for target"）
#   frameworks/native    0001  libbinder：LP64 的 android::Parcel 縮回 Android 8.0 的 104 bytes（4 個 bool 塞進
#                              mError 後面的填充、拿掉沒人用的 mReserved）。ASUS 的指紋 blob（Oreo）把 Parcel 放在
#                              堆疊上只留 104 bytes，A15 的 120 bytes 建構子寫出界 -> stack corruption。
#                              比 120 小對其他人都安全（照 120 編的只是多出空位）。ILP32 仍是 56（Oreo 是 52）
#   hardware/interfaces  0001  audio HAL service：非 Treble（ro.treble.enabled=false）不開 /dev/vndbinder。
#                              legacy linker 只有一個 namespace，libbinder_ndk 與這支共用同一個 ProcessState：
#                              - 開了 vndbinder 再縮 threadpool -> abort（18 個 tombstone -> system_server watchdog）
#                              - 第一版只擋 abort，但行程裡的 AIDL 服務（藍牙音訊 IBluetoothAudioProviderFactory）
#                                因此註冊到 vndservicemanager -> 框架找不到 -> 藍牙 app 一直等、設定沒回應
#                              ⚠ 換 patch 內容時，原始碼樹裡舊版的修改要先 git checkout 掉，不然兩個方向都套不上
#   hardware/interfaces  0002  sensors@1.0-service 的 rc 加 group input（原廠就有）：ASUS 的光線 / 距離 HAL 讀
#                              /dev/input/event*（root:input 0660），少了 input 就開不起來、一個事件都沒有
#                              （log 只看得到 "set EVIOCSCLOCKID failed"；註冊照樣回 OK）
set -e -o pipefail

SRC=${SRC:-$HOME/lineage-22.2}
PROJ=${PROJ:-$(cd "$(dirname "$(realpath "$0")")/.." && pwd)}   # device tree 的根目錄
P=$PROJ/patches

cd "$P"
find . -name '*.patch' | sort | while read -r f; do
    proj=$(dirname "${f#./}")
    name=$(basename "$f")
    if git -C "$SRC/$proj" apply --reverse --check "$P/$f" 2>/dev/null; then
        echo "  已套  $proj  $name"
    elif git -C "$SRC/$proj" apply --check "$P/$f" 2>/dev/null; then
        git -C "$SRC/$proj" apply "$P/$f"
        echo "  套上  $proj  $name"
    else
        echo "!!! 套不上：$proj  $name" >&2
        exit 1
    fi
done
