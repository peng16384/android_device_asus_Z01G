#!/usr/bin/env bash
#
# 22.2：找 PRODUCT_SOONG_NAMESPACES 之間同名的模組（在 lineage22 distro 內）
#
#   bash device/asus/Z01G/tools/128_namespace_dups_22.sh
#
# soong 遇到「同一個模組名出現在多個 namespace、又被 PRODUCT_PACKAGES 裝進去」一次只報一個
# （found in multiple namespaces ... when including in system partition）。
# 這支一次列齊，免得每輪 build graph（~15 秒 + breakfast）只修一個。
set -e -o pipefail

SRC=${SRC:-$HOME/lineage-22.2}
cd "$SRC"

NS="vendor/asus/Z01G vendor/asus/Z01G-oneplus device/asus/Z01G hardware/qcom-caf/msm8998
    hardware/qcom-caf/wlan vendor/qcom/opensource/dataservices hardware/qcom-caf/common/libqti-perfd-client
    vendor/qcom/opensource/data-ipa-cfg-mgr-legacy-um hardware/qcom-caf/thermal-legacy-um"

tmp=$(mktemp)
for ns in $NS; do
    [ -d "$ns" ] || continue
    find "$ns" -name Android.bp -not -path '*/.git/*' -print0 |
        xargs -0 -r grep -hoE '^\s*name:\s*"[^"]+"' |
        sed -E 's/.*"([^"]+)"/\1/' | sort -u | sed "s|\$| $ns|"
done > "$tmp"

dups=$(awk '{print $1}' "$tmp" | sort | uniq -d)
if [ -z "$dups" ]; then
    echo "沒有跨 namespace 的同名模組"
else
    echo "跨 namespace 的同名模組："
    for d in $dups; do
        printf '  %-55s %s\n' "$d" "$(awk -v n="$d" '$1==n{print $2}' "$tmp" | tr '\n' ' ')"
    done
fi
rm -f "$tmp"
