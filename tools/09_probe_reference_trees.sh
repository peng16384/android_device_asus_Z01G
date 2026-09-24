#!/usr/bin/env bash
# 探測參考 device tree 的存在性與分支
#
# 只做 git ls-remote（不下載內容），先確認哪些 repo / branch 真的有，
# 再決定要 clone 哪些。
#
# 分三類：
#   A. 同機種（ZS551KL / Z01G）—— fstab、分割資訊最準，但多半只有 recovery 樹
#   B. msm8998 + A-only 的 LineageOS 16.0 機種 —— 骨架與 proprietary-files.txt 來源
#   C. common tree —— msm8998 平台共用部分
set -uo pipefail

# GitHub 對不存在的 repo 會回 401 並要求帳密，在非互動 shell 會直接卡死。
# 這兩個變數讓 git 遇到要認證時直接失敗而不是等輸入。
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/true
export GIT_CONFIG_NOSYSTEM=1

# 每個 ls-remote 最多 25 秒
TO="timeout 25"

probe() {
    local desc="$1" url="$2" ref="${3:-}"
    local out
    if [ -n "$ref" ]; then
        out=$($TO git ls-remote --heads "$url" "$ref" 2>/dev/null)
        if [ -n "$out" ]; then
            printf '  [有]   %-46s %s\n' "$desc" "$ref"
        else
            # 分支不存在時，列出前幾個可用分支
            local heads
            heads=$($TO git ls-remote --heads "$url" 2>/dev/null | sed 's#.*refs/heads/##' | head -6 | tr '\n' ' ')
            if [ -n "$heads" ]; then
                printf '  [無此分支] %-42s 可用: %s\n' "$desc" "$heads"
            else
                printf '  [repo 不存在] %s\n' "$desc"
            fi
        fi
    else
        if $TO git ls-remote --exit-code "$url" >/dev/null 2>&1; then
            printf '  [有]   %s\n' "$desc"
        else
            printf '  [repo 不存在] %s\n' "$desc"
        fi
    fi
}

echo "=== A. 同機種 ZS551KL / Z01G ==="
probe "shakalaca/android_device_asus_Z01G"      https://github.com/shakalaca/android_device_asus_Z01G
probe "TeamWin/android_device_asus_Z01G"        https://github.com/TeamWin/android_device_asus_Z01G
probe "shakalaca/android_kernel_asus_msm8998"   https://github.com/shakalaca/android_kernel_asus_msm8998

echo
echo "=== B. msm8998 參考機（LineageOS 16.0）==="
probe "oneplus dumpling (5T)"  https://github.com/LineageOS/android_device_oneplus_dumpling      lineage-16.0
probe "oneplus cheeseburger (5)" https://github.com/LineageOS/android_device_oneplus_cheeseburger lineage-16.0
probe "xiaomi sagit (Mi6)"     https://github.com/LineageOS/android_device_xiaomi_sagit          lineage-16.0
probe "essential mata (PH-1)"  https://github.com/LineageOS/android_device_essential_mata        lineage-16.0
probe "sony yoshino (XZ1)"     https://github.com/LineageOS/android_device_sony_yoshino          lineage-16.0

echo
echo "=== C. common tree ==="
probe "oneplus msm8998-common" https://github.com/LineageOS/android_device_oneplus_msm8998-common lineage-16.0
probe "xiaomi msm8998-common"  https://github.com/LineageOS/android_device_xiaomi_msm8998-common  lineage-16.0

echo
echo "=== D. vendor blobs 參考（TheMuppets）==="
probe "TheMuppets oneplus" https://github.com/TheMuppets/proprietary_vendor_oneplus lineage-16.0
probe "TheMuppets xiaomi"  https://github.com/TheMuppets/proprietary_vendor_xiaomi  lineage-16.0
