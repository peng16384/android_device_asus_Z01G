#!/bin/bash
# 比對「我們建出來的 system」與「原廠 system」裡同名函式庫，
# 找出 blob 被 AOSP 模組蓋掉（或反過來）的情形。
#
# 為什麼要這支：
#   第一次開到開機動畫後，logcat 顯示四個 vendor service 因為
#   「symbol not found」而 crash loop：
#     keymaster@3.0-impl -> keymaster::SoftKeymasterContext::ParseKeyBlob
#     wifi@1.0-service   -> android::wifi_system::InterfaceTool vtable
#     media.omx@1.0-service -> ...OmxStore
#   這類錯誤都是「Oreo 的執行檔配 Pie 的函式庫」或反過來造成的，
#   單看檔案在不在沒用，要看同一條路徑上放的是哪一邊的版本。
OUT=$HOME/lineage-16.0/out/target/product/Z01G/system
STK=/mnt/zs_system

check() {
    local f="$1" o="$OUT/$1" s="$STK/$1" bs="-" ss="-" r="-"
    [ -f "$o" ] && bs=$(stat -c%s "$o")
    [ -f "$s" ] && ss=$(stat -c%s "$s")
    if [ -f "$o" ] && [ -f "$s" ]; then
        cmp -s "$o" "$s" && r="原廠blob" || r="AOSP編的"
    elif [ -f "$o" ]; then r="只有我們有"
    elif [ -f "$s" ]; then r="只有原廠有"
    fi
    printf "%-48s built=%-9s stock=%-9s %s\n" "$f" "$bs" "$ss" "$r"
}

for f in "$@"; do check "$f"; done
