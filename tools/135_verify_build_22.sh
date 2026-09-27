#!/usr/bin/env bash
#
# 22.2：刷機前驗證成品（在 lineage22 distro 內）
#
#   bash device/asus/Z01G/tools/135_verify_build_22.sh
#
# 16.0 的 tools/25 那幾項（分割區大小、zip 完整性、boot header、kernel / DTB），加上 22.2 這次特有的：
#   - updater-script 只寫 boot 與 system（安全規則），且走 bootdevice 路徑（TWRP 上實刷過的那種）
#   - first stage 的 fstab 在 ramdisk 裡、cmdline 有 androidboot.boot_devices
#   - 設定檔那一輪的關鍵檔案都有裝上
# 任何一項不過就回非 0。
set -o pipefail

SRC=${SRC:-$HOME/lineage-22.2}
PROJ=${PROJ:-$(cd "$(dirname "$(realpath "$0")")/.." && pwd)}   # device tree 的根目錄
O=${OUT_DIR:-$SRC/out}/target/product/Z01G
ZIP=$(ls -t "$O"/lineage-22.2-*-UNOFFICIAL-Z01G.zip 2>/dev/null | head -1)
[ -n "$ZIP" ] || { echo "!!! 找不到 zip" >&2; exit 1; }
fail=0
ok()  { printf '  OK    %s\n' "$*"; }
bad() { printf '  !!!   %s\n' "$*"; fail=1; }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

echo "=== 產物 ==="
ls -l "$ZIP" "$O/boot.img" "$O/recovery.img" | awk '{printf "  %12d  %s\n", $5, $NF}'

echo "=== 分割區大小 ==="
for x in "boot.img 33554432" "recovery.img 33554432" "system.img 5368709120"; do
    set -- $x; s=$(stat -c %s "$O/$1")
    if [ "$1" = system.img ]; then s=$(python3 -c "
import struct,os
p='$O/system.img'; h=open(p,'rb').read(28)
m,maj,mn,fh,ch,bs,tb=struct.unpack('<IHHHHII',h[:20])
print(bs*tb if m==0xed26ff3a else os.path.getsize(p))"); fi
    # system.img 是 sparse：檔案系統照分割區大小建（必然 100%），實際內容看 build log 的 system.img 大小
    chk "$(printf '%-13s %11d / %11d  (%.1f%%)' $1 $s $2 $(awk "BEGIN{print $s/$2*100}"))" "[ $s -le $2 ]"
done

echo "=== zip ==="
chk "zip 完整（unzip -t）" "unzip -tq '$ZIP' >/dev/null 2>&1"
US=$(unzip -p "$ZIP" META-INF/com/google/android/updater-script)
writes=$(printf '%s\n' "$US" | grep -oE '/dev/block/[A-Za-z0-9_/.-]+' | sort -u)
echo "$writes" | sed 's/^/        updater-script 碰到：/'
chk "updater-script 只碰 boot 與 system" \
    "[ \"\$(printf '%s\n' \"\$writes\" | grep -vE '/by-name/(boot|system)$' | wc -l)\" = 0 ]"
chk "system / boot 走 bootdevice 路徑（TWRP 實刷過的那種）" \
    "! printf '%s\n' \"\$writes\" | grep -q '^/dev/block/by-name/'"
chk "沒有 firmware / radio 的更新（安全規則 1）" \
    "! printf '%s\n' \"\$US\" | grep -qiE 'firmware-update|RADIO/|modem|xbl|abl|tz\\.mbn'"

echo "=== boot.img ==="
info=$(python3 "$PROJ/tools/bootimg.py" info "$O/boot.img")
get() { printf '%s' "$info" | python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }
chk "header v0、page 4096"                 "[ $(get header_version) = 0 ] && [ $(get page_size) = 4096 ]"
# second_addr：22.2 的 mkbootimg 在 second_size=0 時寫 0（16.0 是 0xf00000）；沒有 second 映像，bootloader 不看
chk "kernel_addr 0x8000 / ramdisk 0x1000000 / tags 0x100（與原廠一致）" \
    "[ $(get kernel_addr) = 0x8000 ] && [ $(get ramdisk_addr) = 0x1000000 ] && [ $(get tags_addr) = 0x100 ]"
cmd=$(get cmdline)
chk "cmdline 有 androidboot.boot_devices=soc/1da4000.ufshc" "printf '%s' \"\$cmd\" | grep -q 'androidboot.boot_devices=soc/1da4000.ufshc'"
chk "cmdline 沒有 androidboot.selinux=permissive（2026-09-26 起 enforcing；permissive 版見 tools/139）" "! printf '%s' \"\$cmd\" | grep -q 'androidboot.selinux=permissive'"
# ASUS 的 ABL：最終 cmdline 上限 1024，ABL 自己會附加約 600 -> header 超過 400 就停在 Powered by android
chk "header cmdline $(printf '%s' "$cmd" | wc -c) bytes ≤ 400（ABL 最終上限 1024，它會再加約 600）" \
    "[ \$(printf '%s' \"\$cmd\" | wc -c) -le 400 ]"
kc=$(python3 "$PROJ/tools/kernelcheck.py" "$O/boot.img" 2>&1)
printf '%s\n' "$kc" | grep -iE "version|msm-id|model" | head -8 | sed 's/^/        /'
chk "kernel 是 4.4.302"                       "printf '%s' \"\$kc\" | grep -q '4\.4\.302'"
chk "有本機的 DTB（msm-id 292, 0x00020001）"  "printf '%s' \"\$kc\" | grep -qiE '292.*0x0*20001'"

echo "=== ramdisk（first stage）==="
R=$O/ramdisk
chk "first stage fstab（fstab.qcom）在 ramdisk" "find '$R' -name 'fstab.qcom' | grep -q ."
chk "fstab 的 /system 是 first_stage_mount 且沒有 /vendor 條目" \
    "f=\$(find '$R' -name fstab.qcom | head -1); grep -q 'first_stage_mount' \$f && ! grep -qE '^\S+\s+/vendor\s' \$f"

echo "=== 設定檔那一輪的關鍵檔案 ==="
for f in system/vendor/etc/init/hw/init.target.rc system/vendor/etc/init/hw/init.qcom.rc \
         system/vendor/etc/ueventd.rc system/vendor/etc/fstab.qcom \
         system/vendor/bin/hw/android.hardware.vibrator-service.z01g \
         system/vendor/etc/mixer_paths_tasha.xml system/vendor/etc/audio_platform_info.xml \
         system/vendor/etc/acdbdata/Z01G_MP/Z01G_Speaker_cal.acdb \
         system/vendor/usr/keylayout/goodixfp.kl system/vendor/usr/keylayout/gpio-keys.kl \
         system/vendor/etc/media_profiles_V1_0.xml system/etc/firmware/adsp.mdt \
         system/vendor/firmware/a530_pfp.fw system/vendor/bin/gxFpDaemon system/vendor/bin/sensors.qcom; do
    chk "$f" "[ -e '$O/$f' ]"
done
# 條數檢查擋不住 dump 裡那份通用版（783 條）-> 直接比對內容與 ASUS 原檔相同，並確認喇叭路徑在
# extract-files.py 的 fixup 在最上層預設值加了兩行（TAS2557 組態 21）；兩邊用同一個規則拿掉這類行之後要逐 byte 相同
chk "mixer_paths_tasha.xml = ASUS 的 mixer_paths_ZS551KL.xml + 預設組態 21 + 通話路徑的組態 24/25 與 MonoMix（tools/143）"     "python3 $PROJ/tools/143_check_mixer_paths.py '$O/system/vendor/etc/mixer_paths_tasha.xml' \"\$HOME/asus/dump/system/etc/mixer_paths_ZS551KL.xml\""
chk "mixer_paths_tasha.xml 有 'low-latency-playback speaker'（喇叭，PRI_MI2S_RX 後端）" \
    "grep -q 'path name=\"low-latency-playback speaker\"' '$O/system/vendor/etc/mixer_paths_tasha.xml'"
chk "a530_pfp.fw 是 linux-firmware 1.87.01（WHERE_AM_I）" \
    "[ \"\$(sha256sum '$O/system/vendor/firmware/a530_pfp.fw' | cut -c1-8)\" = 7ab3cd91 ]"
chk "root 有 /asusfw、/factory、/firmware、/bt_firmware、/dsp、/persist" \
    "( for d in asusfw factory firmware bt_firmware dsp persist; do [ -e '$O/root/'\$d ] || [ -L '$O/root/'\$d ] || exit 1; done )"

echo "=== 2026-09-25 開機動畫那一輪的三個根因 ==="
# gxfingerprint.default.so 把 ro.build.product 讀進 8 bytes 的堆疊緩衝區
bp=$(grep -h '^ro.build.product=' "$O/system/build.prop" | tail -1 | cut -d= -f2)
chk "ro.build.product=$bp 不超過 7 字（gx_ta_start 的 8 bytes 緩衝區）且有對應的 ACDB 目錄" \
    "[ \${#bp} -le 7 ] && [ -d '$O/system/vendor/etc/acdbdata/$bp' ]"
# config.fs 的 vendor/ 條目要真的寫進 system.img（fs_config/Android.bp）
T=$(ls -td "$O"/obj/PACKAGING/target_files_intermediates/*/ 2>/dev/null | head -1)
fc="$T/META/filesystem_config.txt"
for b in pm-service imsdatadaemon cnd; do
    chk "system/vendor/bin/$b 有 capabilities（config.fs）" \
        "grep -E '^system/vendor/bin/$b ' '$fc' | grep -qv 'capabilities=0x0\$'"
done
chk "fs_config_files 不是空的" "[ -s '$O/system/etc/fs_config_files' ]"
# 音訊 HAL：非 Treble 下 libbinder_ndk 與 vndbinder 共用 ProcessState（tools/136 的 patch）
# 第一版只擋 abort（pool 已啟動就不縮），但 AIDL 服務（藍牙音訊）因此註冊到 vndservicemanager、藍牙卡死
chk "hardware/interfaces 的 audio service patch 有套上（非 Treble 不開 vndbinder）" \
    "grep -q 'property_get_bool(\"ro.treble.enabled\"' '$SRC/hardware/interfaces/audio/common/all-versions/default/service/service.cpp'"

echo "=== 2026-09-25 開到桌面那一輪 ==="
# 不強制 VINTF manifest 時 libhidl 每次 getService 都 sleep(1)（那段的錯誤字串只在不強制時才編進去）
chk "libhidlbase 是強制 VINTF manifest 的版本（沒有 'Potential race detected' 的 sleep(1)）" \
    "! strings '$O/system/lib64/libhidlbase.so' | grep -q 'Potential race detected'"
chk "IRadio 宣告 @1.5（qcrild 實際註冊的版本）" \
    "grep -q '@1.5::IRadio/slot1' '$O/system/vendor/etc/vintf/manifest.xml'"
chk "沒有 CACertService（缺 JNI、一次開機當兩萬多次）" \
    "[ -z \"\$(find '$O/system/vendor' -iname '*cacert*')\" ]"
# init 的 copy 會拒讀 0666 的檔案（/factory 全是），所以由腳本讀
chk "USB 序號由 init.z01g.ssn.sh 從 /factory/SSN 寫入、產品名稱有設" \
    "grep -q 'init.z01g.ssn.sh' '$O/system/vendor/etc/init/hw/init.qcom.usb.rc' && [ -x '$O/system/vendor/bin/init.z01g.ssn.sh' ] && grep -q '^vendor.usb.product_string=' '$O/system/vendor/build.prop'"
# 指紋 HAL 與 Parcel 縮回 104 bytes 的 patch 必須同進同出：有 HAL 沒 patch -> 無限重啟、log 塞爆 /data
chk "LP64 Parcel 是 104 bytes（patches/frameworks/native/0001，舊 blob 在堆疊上只留這麼多）" \
    "grep -q 'static_assert(sizeof(Parcel) == 104)' '$SRC/frameworks/native/libs/binder/Parcel.cpp'"
chk "指紋 HAL 有裝（Home 鍵靠它）" \
    "[ -e '$O/system/vendor/bin/hw/android.hardware.biometrics.fingerprint@2.1-service' ]"

# 舊 blob 自己 new android::Looper，大小要改成 A15 的（extract-files.py 的 binary_regex_replace）
chk "libpreisp_camera 的兩處 Looper 配置改成 0x88（望遠鏡頭）" \
    "python3 -c \"import sys; d=open('$O/system/lib/libpreisp_camera.so','rb').read(); sys.exit(0 if d.count(bytes.fromhex('88202563fff7'))==1 and d.count(bytes.fromhex('8820fff7aee9'))==1 and d.count(bytes.fromhex('70202563fff7'))==0 else 1)\""
# slim_daemon：GPS 改用 ASUS 堆疊後 OnePlus 那份不在了、ASUS 那份也不收（tools/125 的 UNWANTED）-> 有才檢查
chk "slim_daemon（若有）的 Looper 配置改成 0x108" \
    "[ ! -e '$O/system/vendor/bin/slim_daemon' ] || python3 -c \"import sys; d=open('$O/system/vendor/bin/slim_daemon','rb').read(); sys.exit(0 if d.count(bytes.fromhex('00218052fa500094'))==1 and d.count(bytes.fromhex('e00b1b32fa500094'))==0 else 1)\""

# Widevine：libwvhidl 的 NEEDED 要指向不撞名的 v29 protobuf
chk "Widevine：HAL 在、libwvhidl NEEDED libprotobuf-cpp-lite-v29.so、那個檔也在" \
    "[ -x '$O/system/vendor/bin/hw/android.hardware.drm@1.2-service.widevine' ] && $SRC/prebuilts/clang/host/linux-x86/llvm-binutils-stable/llvm-readelf -d '$O/system/vendor/lib64/libwvhidl.so' | grep -q 'libprotobuf-cpp-lite-v29.so' && [ -f '$O/system/vendor/lib64/libprotobuf-cpp-lite-v29.so' ]"

# GPS 用 ASUS 的整套（OnePlus 的定位堆疊講的 QMI LOC 比這台 modem 新）
chk "GPS：ASUS 的 gnss@1.0-impl-qti + AOSP 的 gnss@1.0-service，沒有 OnePlus 的 gnss@2.0-service-qti" \
    "[ -f '$O/system/vendor/lib64/hw/android.hardware.gnss@1.0-impl-qti.so' ] && [ -x '$O/system/vendor/bin/hw/android.hardware.gnss@1.0-service' ] && [ ! -e '$O/system/vendor/bin/hw/android.hardware.gnss@2.0-service-qti' ] && [ ! -e '$O/system/vendor/lib64/hw/android.hardware.gnss@1.0-impl.so' ]"
chk "GPS：ASUS 的 libloc_core / libloc_pla / libgnss / libloc_api_v02 都在" \
    "( for l in libloc_core libloc_pla libloc_stub libgps.utils liblocation_api libgnss libloc_api_v02; do [ -f '$O/system/vendor/lib64/'\$l.so ] || exit 1; done )"

echo "=== 2026-09-25 桌面之後那一輪 ==="
chk "沒有 /vendor/etc/audio/ 的 ASUS split-A2DP audio policy（會搶走 device tree 那份、A15 解析失敗）" \
    "[ ! -e '$O/system/vendor/etc/audio/audio_policy_configuration.xml' ]"
chk "vendor/firmware/bdwlanc.bin 是指向 /data/vendor/wifi/bdwlan_z01g.bin 的 symlink（OnePlus cnss-daemon 要的檔名）" \
    "[ \"\$(readlink '$O/system/vendor/firmware/bdwlanc.bin')\" = /data/vendor/wifi/bdwlan_z01g.bin ] && [ -x '$O/system/vendor/bin/init.z01g.bdf.sh' ]"
chk "ASUS 的三份 BDF 都在（open / operator / combo）" \
    "( for b in bdwlan_open bdwlan_operator bdwlan_combo; do [ -f '$O/system/vendor/firmware/'\$b.bin ] || exit 1; done )"
chk "開機完成時跑原廠 init.qcom.post_boot.sh（這顆 HMP kernel 沒有 schedutil）" \
    "grep -q 'service qcom-post-boot' '$O/system/vendor/etc/init/hw/init.target.rc' && [ -f '$O/system/vendor/bin/init.qcom.post_boot.sh' ]"
chk "Wi-Fi MAC：wlan_mac.bin 指向 /factory/wlan_mac.bin（讀不到就是隨機 MAC）" \
    "[ \"\$(readlink '$O/system/vendor/firmware/wlan/qca_cld/wlan_mac.bin')\" = /factory/wlan_mac.bin ]"
chk "藍牙位址：libbtnv 是 ASUS 版（讀 /factory/bt_nv.bin；OnePlus 版讀 persist -> 22:22 隨機位址）" \
    "strings '$O/system/vendor/lib64/libbtnv.so' | grep -qx /factory/"
chk "sepolicy：ueventd 與藍牙 HAL 可讀 factory_file" \
    "grep -qE '[(]allow ueventd(_[0-9]+)? factory_file' '$O/system/vendor/etc/selinux/vendor_sepolicy.cil' && grep -q '(allow hal_bluetooth_qti factory_file' '$O/system/vendor/etc/selinux/vendor_sepolicy.cil'"

echo "=== 感測器 ==="
chk "/persist 是真目錄（不是 symlink）且 init 會 bind mount（sensors.qcom 對 sns.reg 做 realpath 檢查）" \
    "[ -d '$O/root/persist' ] && [ ! -L '$O/root/persist' ] && grep -q 'mount none /mnt/vendor/persist /persist bind' '$O/system/vendor/etc/init/hw/init.target.rc'"
chk "光線 / 距離感測器的 sysfs 節點 chown 給 system（HAL 要寫 switch）" \
    "grep -q 'chown system shell /sys/class/sensors/psensor/switch' '$O/system/vendor/etc/init/hw/init.target.rc'"
chk "sensors HAL 有 input 群組（光線 / 距離的事件從 /dev/input 讀；patches/hardware/interfaces/0002）" \
    "grep -qE '^ +group .*\binput\b' '$O/system/vendor/etc/init/android.hardware.sensors@1.0-service.rc'"

echo "=== SELinux 第一批 ==="
chk "fpseek 的屬性名已換成 vendor.asus.fp.hwmodule（ro.hardware.fingerprint 只准 init 寫）" \
    "grep -qa 'vendor.asus.fp.hwmodule' '$O/system/vendor/bin/fpseek' && ! grep -qa 'ro.hardware.fingerprint' '$O/system/vendor/bin/fpseek'"
chk "libpreisp_camera 改讀 /vendor/etc/preisp.xml，且檔案在（vendor 網域不准讀 system_file）" \
    "grep -qa '/vendor/etc/preisp.xml' '$O/system/lib/libpreisp_camera.so' && [ -f '$O/system/vendor/etc/preisp.xml' ]"
chk "audbg 兩支腳本在 /vendor/bin，rc 指向那裡" \
    "[ -f '$O/system/vendor/bin/init.asus.audbg.sh' ] && [ -f '$O/system/vendor/bin/init.asus.checkaudbg.sh' ] && grep -q '/vendor/bin/init.asus.audbg.sh' '$O/system/vendor/etc/init/hw/init.target.rc'"
chk "政策裡有 gx_fpd / fpseek / modem_country 網域與 exec 標記" \
    "grep -q 'gx_fpd_exec' '$O/system/vendor/etc/selinux/vendor_file_contexts' && grep -q 'fpseek_exec' '$O/system/vendor/etc/selinux/vendor_file_contexts' && grep -rq 'modem_country_exec' '$O/system/product/etc/selinux/'"

echo "=== SELinux 第三批（enforcing 開機）==="
chk "BoardConfig 已是 enforcing（boot.img 的 cmdline 沒有 androidboot.selinux=permissive）" \
    "! python3 -c \"import sys;d=open('$O/boot.img','rb').read();sys.exit(0 if b'selinux=permissive' in d[64:576] else 1)\""
chk "gx_fpd / sensors 由 init 直接啟動（腳本 start 要 ctl.start\\\$ 權限、enforcing 下被擋）" \
    "grep -q 'on property:ro.hardware.fingerprint=gx5206' '$O/system/vendor/etc/init/hw/init.target.rc' && ! grep -qE '^service (fpservice|sensor-sh) ' '$O/system/vendor/etc/init/hw/init.target.rc'"
# file_contexts 是「最後符合的那條」生效：用 fc_sort 排好的成品，找最後一條符合 gnss@1.0-service 的
chk "gnss@1.0-service 標成 hal_gnss_qti_exec（最後符合的規則；AOSP 的 gnss@[0-9].[0-9]-service 不能蓋過）" \
    "python3 -c \"
import re,sys
last=None
for l in open('$O/system/vendor/etc/selinux/vendor_file_contexts'):
    p=l.split()
    if len(p)>=2 and not l.startswith('#') and re.fullmatch(p[0], '/system/vendor/bin/hw/android.hardware.gnss@1.0-service'): last=p[-1]
sys.exit(0 if last and 'hal_gnss_qti_exec' in last else 1)\""

echo "=== Vulkan ==="
chk "vendor/lib*/vulkan.msm8998.so 是指到 hw/ 的 symlink（非 Treble 的 default namespace 不找 hw/）" \
    "[ \"\$(readlink '$O/system/vendor/lib64/vulkan.msm8998.so')\" = /vendor/lib64/hw/vulkan.msm8998.so ] && [ \"\$(readlink '$O/system/vendor/lib/vulkan.msm8998.so')\" = /vendor/lib/hw/vulkan.msm8998.so ] && [ -f '$O/system/vendor/lib64/hw/vulkan.msm8998.so' ]"

echo "=== 日常版 ==="
# out/ 是增量的：從 PRODUCT_PACKAGES 拿掉的模組，舊檔會留在 $O/system 裡照樣打包 —— 要看實際產物
chk "bring-up 的 log 管道已拿掉（init.z01g-debug.rc / z01g-snap.sh 會每次開機往 /data 寫 log）" \
    "[ ! -e '$O/system/vendor/etc/init/init.z01g-debug.rc' ] && [ ! -e '$O/system/vendor/bin/z01g-snap.sh' ]"

echo "=== adb ==="
chk "recovery 有設 ro.serialno（bootloader 不給；空的話 Windows 的 adb 讀不到 USB 序號、連 sideload 都不能用）" \
    "grep -q '^ *setprop ro.serialno [^ ]' '$O/recovery/root/init.recovery.qcom.rc'"
adbsec=$(grep -h '^ro.adb.secure=' "$O"/system/etc/prop.default "$O"/system/build.prop 2>/dev/null | tail -1)
echo "        ${adbsec:-ro.adb.secure 沒設}  ← =0 是 bring-up 版（WITH_ADB_INSECURE），日常用的建置必須是 1"

echo "=== sha256 ==="
sha256sum "$ZIP" "$O/boot.img" "$O/recovery.img" | sed 's/^/  /'
[ $fail = 0 ] && echo "全部通過" || echo "!!! 有項目沒過"
exit $fail
