#!/bin/bash
# 找可用的 qcacld-3.0 原始碼（WCN3990 / icnss / msm8998 / LA.UM.6.4）
api() { curl -sS --max-time 20 -H 'Accept: application/vnd.github+json' "$1"; }

echo "=== LineageOS 的 msm8998 kernel 有沒有把 qcacld 放在樹裡 ==="
for repo in LineageOS/android_kernel_oneplus_msm8998 LineageOS/android_kernel_xiaomi_msm8998; do
    for br in lineage-16.0 lineage-17.1; do
        r=$(api "https://api.github.com/repos/$repo/contents/drivers/staging?ref=$br" |
            grep -o '"name": *"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/' | grep -iE 'qcacld|qca-wifi|fw-api' | tr '\n' ' ')
        printf "  %-46s %-14s %s\n" "$repo" "$br" "${r:-（沒有 / 取不到）}"
    done
done

echo
echo "=== CAF 的 qcacld-3.0 鏡像（找 LA.UM.6.4 相關 branch）==="
for repo in andi34/qcacld-3.0 sonyxperiadev/kernel-copyleft; do
    n=$(api "https://api.github.com/repos/$repo" | grep -o '"full_name": *"[^"]*"' | head -1)
    printf "  %-40s %s\n" "$repo" "${n:-取不到}"
done

echo
echo "=== 直接搜尋 GitHub 上的 qcacld-3.0 repo ==="
api "https://api.github.com/search/repositories?q=qcacld-3.0&sort=stars&per_page=8" |
    grep -oE '"full_name": *"[^"]*"|"description": *"[^"]*"' |
    sed 's/"full_name": *"/REPO /; s/"description": *"/  DESC /; s/"$//' | head -20
