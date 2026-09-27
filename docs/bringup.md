# LineageOS 22.2（Android 15）userspace bring-up

> 開始：2026-09-25。kernel 用 4.4.302 + ASUS 驅動（正式版 `z01g_defconfig`）。

## 建置環境（`tools/120`、`tools/121`）

| | 16.0 | 22.2 |
|---|---|---|
| WSL distro | `ubuntu2004`| **`lineage22`** |
| `python` | python2（16.0 的建置腳本）| python3（`python-is-python3`）|
| 原始碼 | `~/lineage-16.0` | `~/lineage-22.2`（`--depth=1`，含 LFS）|

- 另開 distro 的理由：python2 / python3 只能擇一；G: 剩 444 GB 而 16.0 的 vhdx 已 291 GB。
  E: 剩 342 GB（官方建議 400）—— 淺層同步控制大小。N: 是 NAS，太慢不用。
- `%USERPROFILE%\.wslconfig`：`memory` 32GB → **64GB**（lineage-21 以上官方要求 64 GB）。
- rootfs：`focal-server-cloudimg-amd64-root.tar.xz`（cloud-images.ubuntu.com，sha256 對過），Ubuntu 20.04（官方唯一測過的）。

## 架構決定

### vendor 放在 system 裡（`TARGET_COPY_OUT_VENDOR := system/vendor`）

參考的 OnePlus 5（`LineageOS/android_device_oneplus_msm8998-common`，lineage-22.2）是 Treble：
`TARGET_COPY_OUT_VENDOR := vendor`、`BOARD_VENDORIMAGE_PARTITION_SIZE := 1073741824`、
`PRODUCT_FULL_TREBLE_OVERRIDE := true`，fstab 從 `/dev/block/by-name/vendor` 掛 `/vendor`
—— OnePlus 官方後期韌體重新分割出了 vendor 分割區。

ZS551KL 沒有 vendor 分割區，而本專案**不改分割表**（gpt 在絕不寫入名單上）。
可借用的閒置分割區都太小（asdf 128 MB、APD 200 MB、cache 128 MB；vendor blob 就 683 MB）。
-> 與 16.0 相同，vendor 在 system 裡。這台出廠 Android 7.1（API 25），早於「必須 Full Treble」
的門檻（8.1 出廠）。**最大的未知數**：Android 15 / LineageOS 22.2 的建置系統在沒有 vendor image
時要不要打補丁 —— 到 build graph 才會知道。

### blob：SoC 共通借 OnePlus 5，ASUS 專屬用原廠

ASUS 最後一版是 Android 8.0（Oreo）的 blob。OnePlus 5 在 22.2 用的是：
- 主體：`OnePlus/OnePlus5/OnePlus5:10/QKQ1.191014.012/2010292059`（OxygenOS 10）
- RIL、IMS、Bluetooth、CNE、DPM、QMI、ANT+、Power-off alarm：**Fairphone 3 `6.A.025.0`**（SDM632）
—— 連 OnePlus 5 自己都借別台的 RIL/IMS，證實這條路在 msm8998 上走得通。

OnePlus 5 22.2 的 manifest：`target-level="5"`，但仍有 keymaster 3.0、camera.provider 2.4、
composer 2.1、allocator 2.0、sensors 1.0、bluetooth 1.0 —— Android 15 仍接受這些。
audio 6.0（應是原始碼編）、radio 1.4、IMS radio 1.6（FP3 的）。

計畫：
| 用 OnePlus 5（OOS 10 / FP3）的 | 用 ASUS 原廠（1911.117）的 |
|---|---|
| Adreno GPU、多媒體、RIL / IMS、藍牙、CNE / DPM / QMI、Keymaster / Gatekeeper、Widevine、Wi-Fi 設定、thermal、perf | 相機（IMX362/351/319 的 chromatix、ASUS 相機 HAL 相關）、指紋（Goodix gx5206）、感測器（ASH / cm36656 / cm3323e 的 HAL 與設定）、音訊校正（acdb、mixer_paths、TAS2557 韌體）、ADSP / 各子系統韌體（OEM 簽章，必須是 ASUS 的）|

⚠ ADSP / venus / slpi 等韌體**必須用 ASUS 的**：本機熔絲是 ASUS 的 OEM_ID `0x0029` / MODEL `0x0022`，
別家的映像 TZ 會回 `-60`（16.0 踩過，見 CLAUDE.md「ADSP -60」）。

### device tree 骨架

以 22.2 的 `oneplus/msm8998-common` 為底（Android 15 已解決的部分），套上 16.0 累積的 ASUS 設定
（16.0 的 device tree：overlay、system.prop、init rc、sepolicy、media profiles、
audio policy、IMS 的經驗…）。

### OnePlus msm8998-common（22.2）的 BoardConfig 對照

| 設定 | OnePlus 5 | ZS551KL |
|---|---|---|
| `TARGET_COPY_OUT_VENDOR` | `vendor` | `system/vendor` |
| `BOARD_VENDORIMAGE_*` | 1 GB | 拿掉 |
| `BOARD_SYSTEMIMAGE_PARTITION_SIZE` | 3221225472（3 GB）| 5368709120（0x140000000）|
| boot / recovery | 64 MB | 32 MB（33554432）|
| `PRODUCT_FULL_TREBLE_OVERRIDE` | true | **未知**：vendor 在 system 裡時 linker namespace 認不認 `/vendor -> /system/vendor` |
| kernel | `kernel/oneplus/msm8998`、`lineage_oneplus5_defconfig` | `kernel/asus/msm8998`（z01g 分支）、`z01g_defconfig` |
| sepolicy | `device/qcom/sepolicy-legacy-um` + 自己的 | 同 + 16.0 累積的 ASUS 政策 |
| `TARGET_SCREEN_DENSITY` | 420 | 16.0 用的值 |

`common.mk` 裡**從原始碼編**的 HAL（不依賴 blob 年代，對我們有利）：
audio@6.0（`hardware/qcom-caf/msm8998/audio`）、audio.effect@6.0、bluetooth.audio、
camera.provider@2.4 的 impl + service、graphics allocator@2.0 / composer@2.1 / mapper、memtrack。

`lineage.dependencies`：`hardware/oneplus`（OnePlus 專屬：觸控、指紋擴充…，我們不要）、
`kernel/oneplus/msm8998`（我們用自己的）。

參考樹下載在 lineage22 distro 的 `~/ref/`（2026-09-25，`--depth=1`）：
| | 大小 | commit |
|---|---|---|
| `android_device_oneplus_msm8998-common` | 1.7 MB | `213a9c2`（2025-09-24）|
| `android_device_oneplus_dumpling` | 1.1 MB | `673c6b5`（2025-07-16）|
| `proprietary_vendor_oneplus_msm8998-common` | 340 MB，736 檔，無 LFS | `de92024`（2025-04-15）|

## ✅ 架構驗證：build graph 通過（2026-09-25）

`breakfast Z01G` + `m nothing` rc=0（PLATFORM_VERSION=15、BUILD_ID=BP1A.250505.005、
TARGET_RELEASE=bp1a）。**非 Treble、vendor 在 system 裡，22.2 的建置系統不用打補丁。**

- linkerconfig：`ro.treble.enabled != true` 時用 legacy 設定（`system/linkerconfig/main.cc:283`）；
  而且 22.2 明確拒絕「Treble + VNDK-lite」（`main.cc:420`）—— 所以只能純 legacy。
- `BOARD_VNDK_VERSION` 在 22.2 已被清掉（`build/make/core/config.mk:1341`）；prebuilts/vndk 剩 v30~v34。
- 22.2 的 `breakfast` 不做 roomservice，只 `lunch lineage_Z01G-bp1a-userdebug`（非官方機型直接用）。
- OnePlus 5 與 ZS551KL 都是 `PRODUCT_SHIPPING_API_LEVEL := 25`（7.1 出廠）。

這一輪的 vendor 是**暫時**借 OnePlus 的整棵 vendor tree（`tools/123`：namespace 改指、
剔除 3 個依賴 `hardware/oneplus` 介面的模組）。正式的 blob 清單見後面「正式 blob 清單」一節。

## blob 清單的原則

1. **經 PIL 載入的韌體一律用 ASUS 的**：adsp、venus、slpi、a540_zap、modem 相關…
   TZ 驗 OEM 簽章（熔絲 OEM_ID `0x0029` / MODEL `0x0022`），別家的會 `-60`（16.0 的 ADSP 教訓）。
   OnePlus 的 `vendor/firmware/a540_zap.*` **不能用**。
2. **Adreno microcode（kgsl 直接讀，不經 PIL，不驗簽）**：`a530_pfp.fw` 用 **linux-firmware 1.87.01**
   （kernel 移植時實測過；`WHERE_AM_I` 必需）。OnePlus 的是 `0x005ff112`，依 freedreno 的判準不算
   支援 WHERE_AM_I，未實測前不用。`a530_pm4.fw`：ASUS 與 linux-firmware 相同（`5b487d0e`）。
3. SoC 共通（GPU 的 userspace 驅動、多媒體、RIL/IMS、藍牙、Keymaster…）借 OnePlus 5（OOS 10 / FP3）。
4. ASUS 專屬（相機、指紋、感測器、音訊校正、TAS2557 韌體、/asusfw 的內容）用原廠 1911.117。

## ✅ 正式 blob 清單：build graph 通過（2026-09-25）

兩個 vendor 模組，各自抽取（extract_utils 一次只吃一個來源）、互相 import namespace：

| 模組 | 來源 | 條數 | 大小 |
|---|---|---|---|
| `vendor/asus/Z01G` | ASUS 1911.117（`tools/126` 的 `~/asus/dump`）| vendor 2437 + system 韌體 219 + system 其他 34 | 508 MB |
| `vendor/asus/Z01G-oneplus` | TheMuppets OnePlus 5（OOS 10 / FP3）| 429 | 153 MB |

流程：`tools/125`（產清單）→ `tools/127`（放 device tree + 抽兩個模組）→ `tools/124`（build graph）。
排錯用：`tools/128`（跨 namespace 同名模組）、`tools/129`（ASUS 清單 vs 22.2 原始碼的模組名）、
`tools/130`（PRODUCT_COPY_FILES vs soong 安裝路徑）。三支都是「一次列齊」——
soong / Kati 一輪只報一個錯，而每輪要 20 秒～2 分鐘，靠 build graph 逐一撞會花上十幾輪。

### ASUS 那一側的排除規則（`tools/125`，每條排除原因都寫進報告）

| 規則 | 排除 | 內容 |
|---|---|---|
| 1 OnePlus 已提供（同檔名 / 同模組名）| 297 | 同一個 QTI 堆疊不混新舊版本；模組名 = 檔名 + `MODULE_SUFFIX` |
| 2 22.2 從原始碼編 / device tree 提供 | 266 | AOSP HAL、CAF 的 display/IPA/wlan/perf-client、Oreo 時代一起放進 vendor 的 AOSP 元件（`vendor/bin/sh`、wpa_supplicant、soundfx…）、device.mk 已 copy 的路徑、原廠 kernel 的 `lib/modules/` |
| 3 不要的功能 | 100 | NFC、ANT、FM、eSE、wigig、MMI 工廠測試、ASUS 相機 App 的 JNI |
| 4/5 init rc、App、framework、overlay | 81 | |
| 6 屬於 OnePlus 接手的堆疊（依賴封閉）| 61 | NEEDED 了「讓給 OnePlus、但 OnePlus 沒有該架構」的庫 → 一起走，遞迴。另有 `OP_STACK` 列檔名對不上的（iop、perfd、BT hidlclient、Oreo 的 vendor.qti.gnss@1.0 與 Izat）|
| 7 原廠就載不起來 | 15 | NEEDED 的庫在原廠映像根本不存在（libmm-qdcm-diag、libllvd_smore…）；不收 = 原廠行為 |

`rfsa/` 底下是 aDSP 上跑的程式（NEEDED 由 DSP 端解析，`libgcc.so` 等），規則 6 / 7 不看。

### 幾個決定

- **`libQSEEComAPI` 兩個架構都用 ASUS 的**：keymaster / 指紋 / HDCP / PlayReady 都是 ASUS 的 TZ app，
  且要 32 位元版（OnePlus 只有 lib64）。OnePlus 的 `libqisl` / `libspl` 也改連 ASUS 這份。
- **指紋是過度連結的**：7 個檔 NEEDED 一整串 Oreo 的 system 庫，但 `nm -D` 比對用到的符號數是 0
  （libkeystore_binder、libbacktrace、libunwind、ld-android、四個 keymaster 庫、libandroid_runtime、
  libprotobuf-cpp-lite、liblzma）→ `extract-files.py` 用 `remove_needed` 拿掉，不必帶 Oreo 的庫。
- **`libstdc++`** → `libstdc++_vendor`（bionic 只有它有 vendor variant）。
- ⚠ 查 NEEDED 時 **`~/asus/dump` 的 `vendor/` 在最上層**，不在 `system/` 底下。一度只掃 `system/`
  就下了「libkeymaster1 / libpreisp 沒人用」的結論 —— 錯的，相機 HAL 與指紋都要。

### 設定檔那一輪要回頭處理的（清單裡刻意讓給 device tree，但 device tree 現在放的是 OnePlus 的）

- `audio_platform_info.xml`、`graphite_ipc_platform_info.xml`（音訊決定用 ASUS 的）
- `sec_config`、`msm_irqbalance.conf`、`public.libraries.txt`
- `WCNSS_qcom_cfg.ini`（ASUS 的值要逐項比對新 qcacld 的 key）
- ASUS 的 `vendor/ueventd.rc`：要挑需要的節點併進 device tree
  （⚠ 更正：goodix_fp、LaserSensor 這些 ASUS 節點**不在** ueventd 裡，是 init.asus.rc 用 chown 設的）

## 設定檔：OnePlus 骨架換成 ASUS 的（2026-09-25）

| 項目 | 做法 |
|---|---|
| fstab | 沒有 `/vendor`；`/system` 用 `/dev/block/by-name`（first stage）；加 `/asusfw`（`context=`、`ro,noload`）與 microSD；**/data 先不加密**（Android 13 已移除 FDE，FBE 等能開機再開）|
| cmdline | 補 `androidboot.boot_devices=soc/1da4000.ufshc` —— bootloader 只給 `androidboot.bootdevice`，first stage 拿不到 boot device 就不會建 `/dev/block/by-name` |
| 根目錄 symlink | `/firmware`、`/bt_firmware`、`/dsp` -> Treble 路徑：ASUS 的 keymaster / 指紋 / HDCP 寫死從 `/firmware/image` 載 TZ app |
| init | `init.qcom.rc` 留 OnePlus 的（拿掉 dashd、fingerprint_detect、sensors.qti）；ASUS 專屬放 `init.target.rc`（指紋鏈、sensors.qcom、相機節點、audbg、SAR、modem_country、hvdcp_opti）|
| qseecomd 就緒旗標 | OnePlus 的 qseecomd 設 `vendor.sys.listeners.registered`，ASUS 的 keymaster / gatekeeper 等 `sys.listeners.registered` -> `init.target.rc` 橋接。**不接起來 keymaster 無限等待、開不了機** |
| ueventd | 從 ASUS 那份挑 13 條 msm8998 用得到的節點 |
| 音訊 | audio HAL 是**原始碼編的 CAF 版**（16.0 用的是 ASUS blob）。它依音效卡名找 `mixer_paths_tasha.xml` -> ASUS 的 `mixer_paths_ZS551KL.xml` 改名安裝；ACDB 以 `Z01G` 再裝一份；`audio_platform_info.xml` 用 ASUS 的；policy / volumes / effects 用 OnePlus 的（已有 Earpiece / Telephony）。屬性照 ASUS：fluencetype none、spkr_prot / vbat 關（TAS2557 不是 WSA）|
| media profiles | `tools/131`：ASUS 原廠 88 個 profile **全部保留**（Android 15 已認得 vga / 2k / 4kdci / qhd，16.0 得剔掉 26 個），只剔 `lpcm` 一個 AudioEncoderCap |
| overlay | 亮度曲線換 ASUS 原廠（OnePlus 的 nits 曲線是量它的面板的）；`config_deviceHardwareKeys=83`；拿掉皮套感測、雙擊喚醒、音量面板在左、OnePlus 色彩模式、OnePlus Doze；**不設 `config_cameraAuxPackageAllowList`**（非空就把望遠藏起來，16.0 踩過）|
| 屬性 | 指紋 Home 鍵那組、audbg、感測器、`ro.frp.pst` 改 frp 分割、拿掉 OnePlus 的 CDMA 設定 |
| keylayout | 16.0 那三份；`gpio-keys.kl` 的 `WAKE_DROPPED` Android 15 已不認得（**整份會作廢**）-> 音量鍵不標、HOME 標 `WAKE` |
| 振動 | ASUS 的 qpnp-haptic 是 **timed_output**，QTI 的 vibrator 服務只認 LED class / input FF -> 自己寫 AIDL 服務（`vibrator/`，V2）|
| manifest | 拿掉沒人註冊的 esepowermanager / fm / soter / sensorscalibrate |

### 完整編譯第一次失敗：kernel 的 `.gitignore` 吃掉了觸控韌體

```
drivers/input/touchscreen/ftxxxx_ex_fun.c:45:11: fatal error: 'ASUS_LIBRA_GIS_CTC_app.i' file not found
```
ASUS 的 Focaltech 驅動用 `#include` 引入 4 個韌體陣列檔（`*_app.i`），而 kernel 的 `.gitignore`
把 `*.i` 當前置處理產物排除 —— 這 4 個檔從來沒進 git。kernel 移植時在 `~/k22/z01g` 的**工作目錄**編，
所以一直沒發現；22.2 樹的 kernel 是從 git 中轉 clone 的，就缺了。`git add -f` 補進（`5e805846`）。
**把 kernel 從工作目錄搬到別處時，先看 `git status --ignored` 裡有沒有原始碼**（這次只有這 4 個）。

### 完整編譯第三次（keep-going）：110 個 check_elf，69 個模組

`tools/133` 加了 `KEEP_GOING=1`（ninja `-k`）—— check_elf 一次只報一個 blob，不這樣做要來回幾十輪。
137 分鐘跑完，錯誤**全部是 check_elf**：

| 類別 | 數量 | 性質 / 處理 |
|---|---|---|
| `android::hardware::details::g{Bn,Bs}ConstructorMap` | 30 個 HIDL 庫 | **真的載不起來**：Oreo 產生的 HIDL 庫引用舊 libhidlbase 的全域變數。`tools/125` 規則 8 自動偵測、連同依賴者遞迴排除（共 86 條，全是 RIL / IMS / CNE / display / perf / wifidisplay / qfp / qvop 這些 OnePlus 接手或不要的；**沒有**相機 / Goodix 指紋 / 感測器 / 音訊）|
| `DT_NEEDED libstdc++.so` 不在 shared_libs | 22 | `libstdc++_vendor` 裝成 `libstdc++_vendor.so`，名字對不上 -> `replace_needed`（清單 `blob-fixups-libstdcxx.txt` 由 `tools/125` 算，40 條）|
| `__aeabi_d2lz` / `d2ulz` / `f2ulz` / `ldivmod`… | 5 個相機庫 | Oreo 的 **liblog / libm 意外匯出**這些 compiler-rt 輔助函式，相機庫靠它們解析；22.2 不再匯出（d2lz 連 libc 都沒有）-> `add_needed('libcompiler_rt.so')` |
| `@LIBC_PRIVATE`、`@ADSPRPC`、`@SDSPRPC` | 4 | `clear_symbol_version`（OnePlus 對 faceproc 也這樣做）|
| `__page_size`、GLES 3 函式、SONAME 與檔名不符 | 3 | 執行期找得到 / 不影響 -> `DISABLE_CHECKELF`（`tools/125` 的 `CHECKELF_OFF`，每條寫理由）|
| 測試 / 除錯工具 | 6 | 不收（mm-*-test、qmi_test_*、diag_mdlog、hal_proxy_daemon、ditbsp、librecovery_updater_msm）|

sepolicy 還是 OnePlus 的：bring-up 先 permissive（init 在 permissive 下對沒標記的服務只記錄錯誤、照樣啟動，
`service.cpp:108`），能開機後再照 16.0 的經驗整理。

封裝階段另外補了：`NEED_KERNEL_MODULE_SYSTEM := true`（Lineage kernel.mk 在沒有 vendor 分割區時
file_list 少了 `vendor/` 前綴）、`AB_OTA_UPDATER := false`（A15 沒設時**預設 true**）、
root 的新路徑都要有 file_contexts 標記（22.2 的 root 在 system.img 裡，e2fsdroid 會擋）、
TWRP 用的 `recovery.fstab`（bootdevice 路徑；TWRP 3.7.0 沒有 `/dev/block/by-name`）與
放寬的裝置斷言（`tools/134`；TWRP 的 `ro.product.device` 是空的）。

## 刷機後：開機的四道關卡（2026-09-25）

### 1. 卡在「Powered by android」：ASUS ABL 的 cmdline 上限

最終 cmdline 上限 **1024 bytes**，ABL 會在 header 的 cmdline 後面再附加約 600 bytes
（dm= verity、面板、`androidboot.id.*`、bootcount…）。超過就停在 Powered by android，
一兩分鐘後自己退回 fastboot / recovery —— 看起來完全像 kernel 開不起來。

逐項二分（每輪只刷 boot）排除了 kernel 本身、os_version / patch level、buildvariant，
最後是 header 長度：**392 能開、429 與 452 卡住、380 能開**。
拿掉 `earlycon`（只有接 UART 才有用）與 `loop.max_part`（OnePlus 帶來的）。
`tools/135` 檢查 header cmdline ≤ 400。

### 2. 開機動畫、adb 不上線：init 的屬性觸發死結

```
vold -> keystore2 android.security.maintenance -> keymaster@3.0（ASUS keystore.msm8998.so）
     -> 等 sys.listeners.registered（Oreo 舊名）-> 永遠沒人設
```
第一版寫成 `on property:vendor.sys.listeners.registered=true` 接過去 —— 但 **init 的屬性觸發動作排在
late-init 那串 trigger 之後**，而 post-fs-data 的 `exec vdc keymaster earlyBootEnded` 就卡在它前面。
連 `start adbd`（也是屬性觸發）都輪不到，所以 USB 描述元失敗。
改在 `on post-fs` 直接 `setprop sys.listeners.registered ${vendor.sys.listeners.registered}`
（init.qcom.rc 的 post-fs 先 `wait_for_prop` 了，本檔排在後面）。

沒有 adb 的除錯管道：`init.z01g-debug.rc`（kmsg / logcat / 狀態快照寫進 `/data`，上一輪另存 `.prev`），
進 TWRP 後 `mount -o ro -t ext4 /dev/block/bootdevice/by-name/userdata /tmp/d` 讀。
（2026-09-26 日常版收尾時移除。）
⚠ TWRP 裡要改 system 先 `twrp mount system` 再 `mount -o remount,rw /system_root`，
檔案在 `/system_root/system/...`；沒掛就 push，會寫進 TWRP 的 tmpfs、重開機蒸發。

### 3. 開機動畫 12 分鐘後整機重開：三個獨立的根因

dropbox：`system_server_pre_watchdog` ×7、`system_server_watchdog`、`system_server_crash`；tombstone 37 個。

| 症狀 | 根因 | 修法 |
|---|---|---|
| **system_server watchdog**：main 卡在 `AudioService.<init>` -> `AudioSystem.isCallScreeningModeSupported` 等 `IAudioPolicyService` | `android.hardware.audio.service` 一啟動就 abort（18 個 tombstone）：`Binder threadpool cannot be shrunk after starting`。它先用 `/dev/vndbinder` 起 threadpool，再 `ABinderProcess_setThreadPoolMaxThreadCount(1)`。Treble 裝置上 libbinder_ndk（LLNDK，system 的 libbinder）與 vendor 的 libbinder 是**兩份** ProcessState；**非 Treble 的 legacy linker config 只有一個 namespace，兩者載的是同一個 `libbinder.so`**，於是縮的是同一個已啟動的 pool | `patches/hardware/interfaces/0001`：pool 已啟動就不再縮（`ABinderProcess_isThreadPoolStarted()`）。`tools/136` 套、`tools/133` 自動呼叫 |
| **system_server crash**：`FingerprintProvider.scheduleInternalCleanup` NPE | AOSP 編的 fingerprint@2.1-service 是 `class late_start` 直接起，比 fpseek / gxFpDaemon 早 -> 打不開 HAL（`error: -2`）**卻照樣註冊** | 照 16.0：`disabled` + `interface`，由 hwservicemanager 第一次 getService 時啟動（`init.target.rc`；它比 `/vendor/etc/init/` 的那份早解析，後者被當重複定義忽略）|
| **gxFpDaemon** 每次啟動 `stack corruption detected`（19 個 tombstone）| `gxfingerprint.default.so` 的 `gx_ta_start()` 把 `ro.build.product` `property_get` 進 **8 bytes 的堆疊緩衝區**（原廠值 `ZS551KL` 剛好 7 字 + NUL）。我們從 OnePlus 範本帶來 `DeviceName=ASUS_Z01GD_1`，22.2 用它產生 `ro.build.product` -> 蓋掉 canary | 拿掉 `DeviceName` / `SystemDevice` -> `Z01G`（與 16.0 相同；ACDB 目錄也對得上）|
| **pm-service 吃滿一顆核心**（97%，81% kernel）、logd 滿載、kmsg 被洗掉、手機發燙 | `msm_ipc_router_bind` 要 `CAP_NET_BIND_SERVICE`，而 **config.fs 的 `vendor/` 條目一條都沒進 system.img**（`META/filesystem_config.txt` 全是 `capabilities=0x0`）：A15 的 `fs_config_files_system` 會略過 `vendor/` 與 `system/vendor/`，vendor 那份只在有 vendor 分割區時才找得到。pm-service 被拒後無限重試 | `patches/build/make/0001`：`fs_config_files_system` 的 `--all-partitions` 拿掉 `vendor`，vendor/ 條目就留在 system 那份（libcutils 會把 `system/vendor/x` 對到 `vendor/x`）。先試過在 device tree 另做一份再 `overrides` —— Soong 對每個模組都產生安裝規則，同一路徑兩個模組，kati 直接報 `overriding commands for target`。`tools/135` 檢查 pm-service / imsdatadaemon / cnd 的 capabilities |

整機重開的直接原因這一輪沒留下來（debug rc 當時還沒有 `.prev`，下一次開機就把 log 蓋掉了）。
pm-service 的空轉 + 反覆 watchdog 是最可能的組合，修好後再看。

### 4. 開到桌面之後：一次開機一個坑（2026-09-25 起）

| 症狀 | 根因 | 修法 |
|---|---|---|
| adb 看不到（裝置管理員有 ADB Interface）| bootloader 不傳 `androidboot.serialno`，USB 沒有 iSerialNumber，Windows adb 直接略過。序號在 `/factory/SSN`；init 的 `copy` 會拒讀 0666 檔（"Skipping insecure file"）| `/factory` 唯讀掛載 + `init.z01g.ssn.sh` |
| 整台卡、SIM 沒反應、藍牙 abort | **不強制 VINTF manifest 時 libhidl 每次 getService 都 `sleep(1)`**；RIL 抓著鎖往下探 IRadio 版本 -> `com.android.phone` 啟動 ANR 192 次 | `PRODUCT_ENFORCE_VINTF_MANIFEST_OVERRIDE`（不帶 `_OVERRIDE` 會被 config.mk 蓋掉）；IRadio 宣告 @1.5 |
| 卡頓 | OnePlus 的 CACertService 缺 JNI，一次開機當 24,005 次 | 不收 |
| 沒聲音 | extract_utils 對 `src:dst` **先找 dst**，dump 裡剛好有通用版 `mixer_paths_tasha.xml` | 改名安裝加 `;TRYSRCFIRST`；tools/135 逐 byte 比對 |
| 發燙、`/data` 被塞滿（log 50.6 GB）| 指紋 HAL 自帶 VINTF 片段 + overlay 宣告了感測器 -> 框架無限重試（HAL 本身因 Parcel ABI 一碰就死）| 指紋 HAL、`config_biometric_sensors` 暫時拿掉；除錯 log 加上限 |
| Widevine 每秒崩潰 | legacy 單一 namespace：vendor 的 `libprotobuf-cpp-lite.so` 被 system 同名的遮住（tools/137「撞名」）| 暫時停用 |
| 藍牙設定沒回應 | audio HAL 開了 vndbinder -> 行程裡的 AIDL 服務（藍牙音訊）註冊到 vndservicemanager | patch 改成非 Treble 不開 vndbinder |
| 藍牙配對了但聲音從喇叭出 | `/vendor/etc/audio/` 的 ASUS split-A2DP 版搶先（16.0 同一個坑），且用了 A15 不認得的 `AUDIO_DEVICE_OUT_ALL_SCO` -> AudioPolicy 退回 `setDefault`，只剩喇叭 | 不收那兩份 |
| 一直溫溫的、DevCheck 看頻率固定 | OnePlus rc 寫 `schedutil`，這顆 HMP kernel 沒有 -> 停在 `performance` | 開機完成時跑原廠 `init.qcom.post_boot.sh`（interactive、core_ctl、devfreq）|
| Wi-Fi 打不開 | OnePlus cnss-daemon 讀 OnePlus 專屬的 `/sys/project_info/hw_id` 選 BDF，讀不到就要 `bdwlanc.bin`（不存在）-> WLAN FW 等不到 BDF、永不 FW_READY | `bdwlanc.bin` -> `/data/vendor/wifi/bdwlan_z01g.bin`，開機依 `ro.boot.id.rf` 照 ASUS 原廠 cnss-daemon 的邏輯（反組譯）挑 open / operator / combo |

查 Wi-Fi 的方法：cnss-daemon 的 log 在 logcat 撈不到，**`strace` 它寫給 `/dev/socket/logdw` 的內容**才看得到；
開機那一次的完整經過在除錯 log 檔裡（`wlfw_send_cap_req` 之後 `Failed to Download the BDF File`）。
`/sys/kernel/debug/icnss/stats` 的 `fw_status 0x5`（缺 0x2 FW_READY）是判斷「卡在 BDF」的關鍵。

### 5. 指紋與 Home 鍵：把 Parcel 縮回 Oreo 的大小（2026-09-25）

ASUS 的 `libfp_client.so`、`fingerprint.gx52*.so`（Oreo 編的）在每個 Bp 方法裡把 `android::Parcel`
放在**自己的堆疊上**（85 處），只留 Oreo 的大小。量法：

| | LP64 大小 | 怎麼量的 |
|---|---|---|
| Oreo | 0x68 = 104 | `BpFingerPrintService::connect` 裡 data / reply 分別在 `x29+0x68`、`x29+0xd0`，相距 0x68 |
| A15 | 0x78 = 120 | `Parcel()` 建構子寫到 `[x0,#0x68]`（`mOwner`，`freeDataNoInit` 從這裡讀），後面還有 `mReserved` |

多出的 16 bytes 蓋掉下一個 Parcel 的開頭與堆疊保護值 -> `stack corruption detected`。
Google 在 `Parcel.cpp` 自己寫了「many things compile this into prebuilts on the stack」，所以把大小凍結在 120 ——
照顧的是比 Oreo 新的預編檔。

`patches/frameworks/native/0001`：4 個 bool 移進 `mError` 後面的對齊填充、拿掉**沒有任何程式碼用到**的
`mReserved` -> `mOwner` 落在 0x60，總長 104，一個有用的欄位都沒刪。比 120 小對其他人是安全的
（照 120 編的只是多出空位），整棵樹又是從原始碼編（`PRODUCT_MODULE_BUILD_FROM_SOURCE`），所以沒有版面不一致。
`static_assert` 改成 104；反組譯確認新建構子只寫到 0x68。重編大半個系統（約 70 分鐘）。

同一份掃描還列出其他在堆疊上建 Parcel 的舊 blob（ASUS `camera.msm8998.so` 等）；
ILP32 的 Parcel 是 56，Oreo 是 52，32 位元的那幾個仍差 4 bytes（目前沒出事）。

Home 鍵不是驅動送的：HAL 連上 gxFpDaemon 之後 daemon 才進 `GF_HAL_WAIT_IMAGE`、把按壓轉成
`HOME KEY DOWN`。沒有 HAL 時它停在 `GF_HAL_IDLE`，手指碰了照樣偵測到，但什麼鍵都不送。
（`config_biometric_sensors` 與指紋 HAL 必須同進同出：宣告了感測器卻沒有 HAL，框架會無限重試。）

### 6. 喇叭電流聲：功放停在開機組態（2026-09-25）

每次播放結束，兩個喇叭都有底噪。逐一排除：PCM 全關、mixer 4,389 個控制項播放前後完全相同、DAPM 全 Off、
PRI_MI2S 腳位有切回 sleep、TAS2557 驅動與功放韌體和原廠逐 byte 相同、`/factory/tas2557_cal.bin` 校正載入也沒用。
**重啟 audio HAL 會消失** —— 重寫一次預設值時驅動印出「device powered up, power down to load program」，
接著 `hw_reset`：軟體關閉序列之後功放仍在有底噪的狀態，硬體重置才安靜。

根因：TAS2557 的「組態」（Stereo Configuration）。ASUS 的音訊 HAL 依用途主動套
`*-dynamic-configuration-*` 這些 mixer 路徑（量產機音樂 = 21、通話 = 24/25/27…）；
22.2 的 CAF HAL 不認得，功放從開機到現在都停在 platform-init 的組態 0（"Tuning Mode_48 KHz_s1_0"）。
手動切 21 -> 雜訊消失、音質也好一點。永久修法：extract-files.py 的 fixup 在 mixer_paths 最上層預設值加
`Stereo Configuration = 21`、`Stereo LDAC Playback Volume = 15`。

⚠ **括號裡原本寫「通話路徑切到 27，還原時回 21」—— 那是錯的**（2026-09-26 發現：聽筒通話過後電流聲又回來）。
voice-handset 路徑是 Program 1 / 組態 27；掛斷時 libaudioroute 依**控制項編號**（不是路徑裡的順序）寫回初始值：
1. 先寫組態 21 —— 這時 Program 還是 1，`tas2557_set_config()` 發現 21 屬於 Program 0，回 `EINVAL` **直接丟掉**
2. 再寫 Program 0 —— `program_put` 換 Program 時用 `set_program(0, -1)`，`-1` = 該 Program 的預設組態 0
3. libaudioroute 快取著「21」（寫入失敗它不管），之後任何路徑再設 21 都**不會真的寫**

所以在 mixer_paths 這層修不了（試過在 speaker 路徑加一行 21，實測無效）。修在 kernel
（`sound/soc/codecs/tas2557s/tas2557-codec.c`）：組態因為屬於別的 Program 被拒時記下來，切到那個 Program 時套用。
實測 dmesg：`configuration 21 pending until program 0 is selected` -> `program 0: applying pending configuration 21`。
kernel 在 boot.img，驗證只要 `fastboot flash boot`。

**通話擴音沒聲音（2026-09-27，同一個根因的另一面）**：擴音通話與 VoIP 的 mixer 路徑
（`voicemmode1/2-call speaker`、`compress-voip-call speaker / handset-for-voip`）先把兩顆 TAS2557 設成
`DevA-Mute-DevB-Mute`，原廠由 ASUS HAL 接著套 `*-dynamic-configuration-call`（組態 24/25 +
`DevA-MonoMix-DevB-MonoMix`）解除；CAF HAL 不會 -> 功放停在全靜音。extract-files.py 把那兩行直接寫進通話路徑
（組態 24/25 都屬 Program 0，與擴音時的 Program 相同，驅動不會拒絕；實測時先用 tinymix 在通話中手動套，
擴音立刻有聲音）。`tools/143` 把成品的修改反向還原後與 ASUS 原檔逐 byte 比對，每處修改必須剛好一次。

### 7. 相機：望遠鏡頭讓整個 HAL 崩潰（2026-09-25）

Open Camera 的主、前鏡頭正常；內建相機開不起來、望遠「占用中」。camera provider 一開 camera 2 就崩潰
（`libpreisp_camera.so` 的 `Looper::pollOnce` 讀到 0x10），CameraService 把所有客戶端踢掉；
內建相機一啟動就列舉所有鏡頭，所以整個 app 起不來。

又是舊 blob 與 A15 C++ 類別的大小：`libpreisp_camera`（Rockchip pre-ISP，32 位元）自己 `new Looper(false)`，
`operator new` 的大小是編譯時寫死的 **0x70**，A15 的 Looper 是 **0x88**（A15 libutils 的 `sp<Looper>::make()`
裡 operator new 的參數）-> 建構子寫出配置範圍、堆積被寫壞。不能像 Parcel 那樣縮 A15 的類別（成員都有用），
改 blob 那條指令就好：extract-files.py 的 `binary_regex_replace` 把兩處 `movs r0, #0x70` 改成 `#0x88`。
同一次掃描（誰 import 了 `Looper::Looper(bool)`）還抓到 OnePlus 的 `slim_daemon`（LP64：0xe0 對 A15 的 0x108），一併改。
`Thread` 也量過：A15 比 Oreo 小，安全。

**這類問題的判準**：舊 blob 呼叫 A15 的**建構子**時，配置的空間是 blob 編譯時決定的
（堆疊上的 Parcel、`operator new(N)` 後接建構子、繼承 A15 類別的子類別）。量 A15 那一側的大小要看它自己配置時用的數字。

### 8. GPS：換回 ASUS 的定位堆疊（2026-09-26）

OnePlus 的 `gnss@2.0-service-qti`（A10）起得來、框架也拿得到能力，但 GPSTest 一顆衛星都沒有。
HAL 的 log 預設幾乎不印；**要 `setprop log.tag V`** 才看得到（`gps.conf` 的 `DEBUG_LEVEL` 單獨調沒用）：
`registerMasterClient` / `setBlacklistSv` 回 `INVALID_MESSAGE_ID`，`setGpsLock` / `setSUPLVersion` /
`setLPPConfig` 回 `INVALID_PARAMETER`（ind 卻是 SUCCESS）—— 它講的 QMI LOC 比這台 ASUS 2019 年的 modem 新，
引擎鎖定解不開，session 起不來（`ERROR: 5` = `LOCATION_ERROR_ID_UNKNOWN`）。

改用 ASUS 的（16.0 驗證過）：`tools/125` 的 `'GPS': ASUS`，並放寬原本寫死「GNSS 歸 OnePlus」的三條規則
（`FROM_SOURCE` 的 `hw/android.hardware.*` 例外 `gnss@1.0-impl-qti`、不再把 `libloc_pla/libloc_stub` 當原始碼編、
`OP_STACK` 只留 `vendor.qti.gnss@*` 與測試工具）。ASUS 只有 impl（16.0 是 system_server passthrough），
A15 用 AOSP 的 `android.hardware.gnss@1.0-service` 當宿主（`registerPassthroughServiceImplementation` 依檔名前綴
找到 `-impl-qti`；AOSP 自己的 `-impl` 不要裝）。manifest 宣告 `gnss@1.0`：FCM 5 的矩陣寫 `2.0-1`，
但 check_vintf 仍判 COMPATIBLE（不算淘汰），不需要 2.0 轉接層。`loc_launcher` 照 ASUS 原廠以 root 啟動
（自己 setuid，群組 `gps inet diag wifi`）。設定檔改用 ASUS 的（device tree 的 OnePlus `configs/gps/` 移除）。

不收：ASUS 的 `slim_daemon`（引用 Oreo HIDL 才匯出的 `sensorservice::V1_0::toString(Result)`，載不起來；
感測器輔助定位，基本定位不需要）、`vendor.qti.gnss@1.0`（Izat 擴充，16.0 也停用）。

### 9. Widevine：HAL 起得來，但上限是 L3（2026-09-26）

OnePlus 的 `drm@1.2-service.widevine` 原本一啟動就 CANNOT LINK：`libwvhidl.so` 要的是 VNDK v29 的
`libprotobuf-cpp-lite.so`，非 Treble 的單一 namespace 先找到 /system 的 A15 版（符號不同）。
改連 Lineage `hardware/lineage/compat` 本來就有、不撞名的 `libprotobuf-cpp-lite-v29`（`replace_needed`），
另加 `libcrypto_shim`。⚠ OnePlus 清單把 `libwvhidl.so` 釘了 hash，extract 會直接沿用備份、不跑新的 fixup
→ `tools/125` 的 `OP_UNPIN` 拿掉那個 hash。manifest 補回 `drm@1.2` 的 ICryptoFactory / IDrmFactory。

結果：HAL 穩定執行，CDM 可用，但 **L1 過不了、退回 L3**：
`LoadLevel1: Could not find /factory/wv.keys. Falling Back to L3`（= TA 回報 keybox 無效）。

**不是移植造成的**，用整套 ASUS 原廠元件逐一排除：

| 試法 | 結果 |
|---|---|
| ASUS 自己的 `is_keybox_valid` + 32 位元 `liboemcrypto.so`（hlos/tz API 都是 13，不再跨版本）| `IsKeyboxValid = 0x7fffffff` |
| 再把 qseecomd 換成 ASUS 的（含 `libdrmfs/librpmb/libssd`）| 一樣；TA 經 listener 找的都是 `/persist/data/widevineAlt`（不存在）|
| 改載 modem 分割的 `/firmware/image/widevine.*` | TZ 拒載（`scm_call to load app failed`，通用簽章，同 ADSP `-60`）|
| `/persist/data/widevine/*` 與原廠時期的 `_docs/backup/persist.img` 比 | 逐檔 sha1 相同，沒被動過 |

也就是 ASUS 的 lib + TA + listener 在這台機器現在的狀態下同樣判 keybox 無效。ASUS 的 keybox 是出廠時
由 `install_key_server`（socket 收工廠工具送來的 keybox）寫進去的，系統端沒有重新佈建的路徑。
推測是解鎖 bootloader 之後 TZ 就不再接受 keybox（沒辦法在鎖定狀態下對照，未證實）。
L3 可以播 Widevine 內容，只是串流平台會限制在 SD 畫質。

### 10. Wi-Fi MAC 與藍牙位址：都在 /factory（2026-09-26）

兩個都是沿用 OnePlus 的「位址放在 persist」慣例，這台 persist 裡沒有 → 退回隨機值：

| | 症狀 | OnePlus 的路徑 | ASUS 的路徑 | 修法 |
|---|---|---|---|---|
| Wi-Fi | `cnss_utils: WLAN MAC address is not set`，每次開機隨機 | `wlan_mac.bin` -> `/mnt/vendor/persist/wlan_mac.bin` | `/factory/wlan_mac.bin`（`Intf0/Intf1MacAddress=`）| `Android.bp` 的 symlink 改指 `/factory` |
| 藍牙 | `22:22:xx` 隨機位址（HAL 產生後寫進 `persist.vendor.service.bdroid.bdaddr`）| `libbtnv` 讀 `/mnt/vendor/persist/bluetooth/` | ASUS 的 `libbtnv` 讀 `/factory/bt_nv.bin` | `libbtnv.so` 改用 ASUS 的（API 相同；`tools/125` 的 `OP_DROP_FILES`）|

藍牙實測（先 bind mount ASUS 的 libbtnv、重啟 HAL）：`BD address read for NV_BD_ADDR_I` -> 位址變成 ASUS OUI `B0:6E:BF`。
QTI HAL 的 NV 優先於那個已經存下來的隨機 persist 屬性，不用手動清。
⚠ 本機位址變了，之前配對的藍牙裝置要重新配對。

sepolicy：`ueventd`（代 qcacld 讀 firmware）與 `hal_bluetooth_qti` 要讀 `factory_file`（`sepolicy/vendor/factory.te`）。

順便排除 ASUS 的 legacy DRM 外掛 `lib{,64}/mediadrm/libwvdrmengine.so`（A15 不載入，只會在 `tools/137` 報撞名）。

### 11. 日常版收尾（2026-09-26）

- 拿掉 bring-up 的 log 管道（`init.z01g-debug.rc`、`z01g-snap.sh`）：每次開機往 `/data` 寫 kmsg / logcat / 快照，
  上限加起來約 250 MB。⚠ `out/` 是增量的，拿掉的模組舊檔會留在 `$OUT/system` 繼續打包 → 要手動刪，
  `tools/135` 檢查實際產物
- `WITH_ADB_INSECURE`：22.2 的建置從來沒帶，`ro.adb.secure=1`（USB 偵錯要在手機上授權）
- 仍是 `userdebug`（`adb root` 要開發人員選項的「Root 權限偵錯」），與 LineageOS 官方建置相同

### 12. 感測器：兩個獨立的缺口（2026-09-26）

**光線 / 距離**（ASUS 的 ALSPS，不走 SSC）：`ALSPS_HAL: psensor open /sys/devices/virtual/sensors/psensor/switch
failed (Permission denied)`，所有註冊回 `INVALID_OPERATION` -> 自動亮度、通話熄螢幕都沒作用。
節點預設 `root:root 0664`，HAL 跑 `system`；原廠 `init.qcom.rc` 的 `ASUS_BSP` 段會 chown，我們的
`init.qcom.rc` 是 OnePlus 那份改的、沒有 -> 抄進 `init.target.rc` 的 `on boot`。執行期手動 chown 後實測註冊變 `OK`。

**加速度計 / 陀螺儀 / 磁力計**（SLPI 上的 SSC）：`dumpsys sensorservice` 只有 2 個感測器，
`sensors.qcom` 每 10 秒重啟（`Timeout waiting for SMGR service`）。SLPI 本身有起來（`Brought out of reset`），
但 IPC router 上 SLPI 節點（node 9）沒有 SMGR（0x100）服務。
- `sensors.qcom` 啟動時 `sns_fsa_la.c: invalid directory path 24` / `Error opening registry file`。
  strace：它 stat 完 `/persist/sensors/sns.reg` 後對 `/persist/sensors` 做 realpath，得到
  `/mnt/vendor/persist/sensors` —— 22.2 的 `/persist` 是 symlink（`BOARD_ROOT_EXTRA_SYMLINKS`），
  不等於預期路徑就拒絕（24 = `/persist/sensors/sns.reg` 的長度）。原廠 / 16.0 的 `/persist` 是真的掛載點。
- 改法：`/persist` 改成 root 的真目錄（`BOARD_ROOT_EXTRA_FOLDERS`），`on fs` 再 bind mount `/mnt/vendor/persist`。
  兩條路徑都是真的，OnePlus 那邊用 `/mnt/vendor/persist` 的也不受影響。
- 執行期驗證只做到一半：realpath 的錯誤消失了，但 SMGR 仍沒出現 —— SMGR 在 SLPI 開機時要不到
  註冊表就放棄、不重試。從開機就是真目錄的建置刷下去：23 個感測器全部出現（ICM20690 加速度 / 陀螺、
  AK09918 磁力，加上 QTI 的融合與手勢感測器），`sensors.qcom` 不再重啟。

**光線 / 距離的第二層**：chown 之後註冊回 `OK`、HAL 也 `switch psensor on OK`，**但一個事件都沒有**
（使用者回報「亮度、距離沒反應」）。唯一的線索是 `set EVIOCSCLOCKID failed` —— HAL 開 `/dev/input/event*`
（`root:input 0660`）失敗，拿無效的 fd 去 ioctl。22.2 從原始碼編的 `android.hardware.sensors@1.0-service.rc`
是 `group system wakelock uhid context_hub`，原廠是 `group system wakelock input`。
`patches/hardware/interfaces/0002` 補 `input`。執行期驗證：chmod 那兩個節點後重啟 HAL，事件立刻進來。
⚠ **「註冊回 OK」不代表有資料**，要看 `dumpsys sensorservice` 的 `Recent Sensor events`。

⚠ **這顆 22.2 的 `/` 就是 system 分割區**（system-as-root，`/dev/block/sda19 on / type ext4`）。
`mount -o remount,rw /` 之後改 root 底下的東西是**寫進 system**、重開機不會還原，不是 ramdisk 的 rootfs。
實測踩到：想暫時把 `/persist` 換成目錄測試，結果改到分割區上，最後重刷 zip 還原。

### 13. SELinux enforcing（2026-09-26）

enforcing 開機、全功能實測正常（指紋 / Home 鍵、23 個感測器、三顆相機、通話、GPS、藍牙、耳機、Wi-Fi）。
被擋的只剩兩條，刻意留著：`ctl.start$iop`（post_boot 想啟動這棵樹沒有的 iop 服務）、`sensors.qcom` 一次
`dac_read_search`（感測器正常；16.0 查過同類的是它降成 nobody 後想開 `/dev/diag`）。

**與 16.0 最大的不同：政策在 `/system`，不在 boot.img。** vendor 在 system 裡 -> `precompiled_sepolicy` 在
`/system/vendor/etc/selinux`，每改一次政策都要刷整包 zip（16.0 只刷 boot.img，10 秒）。boot.img 只剩
enforcing / permissive 這個開關：`tools/139` 做兩顆（`boot-enforcing.img` / `boot-permissive-rollback.img`）。
工具：`tools/138` 只編政策（含 neverallow 與 contexts 測試，幾分鐘）；`tools/94`（主 repo）收 denial。

移植 16.0 的政策（`gx_fpd` / `fpseek` / `modem_country` / `sar_setting` 網域、ASUS 的 device / proc / sysfs /
屬性型別），A15 多擋了這些，全部改用正規做法、沒有開洞：

| A15 的限制（neverallow） | 撞到的 | 做法 |
|---|---|---|
| vendor 網域不准讀 `system_file` | audbg 腳本、`preisp_profiles.xml` 在 /system/etc | 改名裝到 /vendor；`libpreisp_camera.so` 的路徑字串二進位換成 `/vendor/etc/preisp.xml`（同長度）|
| `exported_default_prop` 只有 init / vendor_init 能寫，且 AOSP 已 exact 定義 | `fpseek` 寫 `ro.hardware.fingerprint` | 二進位換成同長度的 `vendor.asus.fp.hwmodule`，init 抄過去 |
| `serialno_prop` 只有 init 能寫 | USB 序號腳本 `setprop ro.serialno` | 腳本只設 `vendor.asus.ssn`，rc 再寫 |
| vendor 網域不准讀系統側屬性型別（**不看 shipping API**，16.0 的 `get_prop(x, default_prop)` 編不過）| 相機 / 音訊 / 指紋 / thermal… | `getprop -Z` 列出那些型別底下實際存在的屬性：有用的（`persist.sys.fp.navigation`）在 vendor 給專屬型別，其餘是查沒設的屬性 -> dontaudit |
| `dac_read_search` 只給少數系統網域 | `sensors.qcom`（root）讀 `system` 擁有的 `sns.reg` | 原廠 persist 備份裡是 root:root —— OnePlus 的 rc 把它 chown 成 system。拿掉那段、開機時 chown 回 root |

enforcing 開機才出現、permissive 看不到的（同 16.0 的教訓）：
- **腳本 `start <服務>` 要 `ctl.start$<服務>` 權限**：`fpservice.sh` 啟動 `gx_fpd`、`init.qcom.sensors.sh` 啟動 `sensors`
  都被擋 -> 改由 init 依屬性 / on boot 直接 start（不給 `qti_init_shell` 啟動服務的權限）
- **GNSS**：AOSP 的 `gnss@1.0-service` 當宿主載 QTI impl，被標成 `hal_gnss_default`，缺 qcom 只給 `hal_gnss_qti` 的
  `location_data_file:dir` -> 改標 `hal_gnss_qti_exec`
- ⚠ **file_contexts 是「最後符合的那條」生效，fc_sort 依開頭固定字串的長度排序**：寫成
  `/(vendor|system/vendor)/bin/...` 固定字串只有 `/`，會排在 AOSP 的 `gnss@[0-9]\.[0-9]-service` 前面而**被蓋掉**
  （編譯不報錯）。要蓋 AOSP / qcom 的標記時，寫死 `/vendor/...` 與 `/system/vendor/...` 兩條。`tools/135` 直接查最後符合的那條
- 註冊表擁有者、`/factory` 的 dir search、Widevine 找 `/factory/wv.keys` 等

audit 丟失：第一輪 `audit_lost=2864`（幾乎全是沒有網域、跑在 init 裡的三支 daemon 洗掉的），給網域之後降到 0–1。

### 14. Vulkan：驅動在 hw/，非 Treble 的載入器不找那裡（2026-09-27）

3DMark 所有測試都「not compatible」。系統宣告 Vulkan 1.1，但 `cmd gpu vkjson` 的 `devices` 是空的
（permissive 也一樣；驅動與 libgsl 都是 OnePlus 的 V@415，版本一致）。

A15 的 libvulkan 用 `android_load_sphal_library("vulkan.msm8998.so")` 載驅動：Treble 裝置在 sphal namespace 找
（搜尋路徑含 `/vendor/lib*/hw`），**非 Treble 只有 default namespace，搜尋路徑是 `/vendor/lib*`、沒有 `hw/`**。
strace 看得很清楚：只試了 `/system/lib64`、`system_ext`、`product`、`/system/vendor/lib64`。
唯一的 log 是 `vndksupport: Could not load vulkan.msm8998.so from default namespace`（標籤不是 vulkan，很容易漏）。
`gpuservice` 開機時就快取了這個結果，之後 `vkjson` 完全不開檔、不下 ioctl。

修法：`Android.bp` 的 `install_symlink` 在 `/vendor/lib{,64}/` 放 `vulkan.msm8998.so` -> `hw/` 的實體檔，
file_contexts 標成跟實體檔一樣的 `same_process_hal_file`（寫死路徑）。結果：`Adreno (TM) 540`、Vulkan 1.1.87、
34 個擴充；3DMark 可以跑。
⚠ 在 enforcing 下用 `cmd gpu vkjson > /data/local/tmp/x` 會得到 `Failed transaction` —— gpuservice 不准寫
shell_data_file；要用管線讀它的輸出。

（3DMark 另外被 LineageOS 的每 App 網路限制擋住下載，是設定問題、與移植無關。）

### 15. kernel：合併 CIP 4.4 SLTS 的修補（2026-09-27）

kernel 早已是 4.4.302（上游 4.4 最後一版）。之後的安全修補只剩 CIP 的 4.4-st 樹（SLTS 到 2027）。
kernel repo 是 4.4.302 的快照、與上游沒有共同歷史 -> 不能 git merge，改用三方合併：
`tools/140`（範圍與合併）、`tools/141`（解單一衝突區塊）、`tools/142`（兩分支從頭編譯、比較警告）。

- **base 不能用上游的 v4.4.302**：CIP 分支從 2017 年就帶著為 Renesas 回移的新功能（OPP、clk 的新 API…），
  `v4.4.302..cipNNN` 會把那些一起算進來。base = `v4.4.302-cip68`（CIP 合併上游 4.4.302 的第一版）
- 範圍 = CIP 改過 ∩ 這顆 kernel 實際編到的檔案（KERNEL_OBJ 的 `.o.cmd` 相依）：719 個，56 處衝突手解
- ⚠ 收集相依時把 190 MB 的 `.cmd` 串給 grep：其中有二進位位元組，**grep 判定成二進位檔就悄悄停止輸出**，
  漏了 `ext4.h` 等 11 個標頭（編譯錯誤才發現）。要 `grep -a`
- ⚠ **文字合得進去 ≠ 語意正確**：CIP 的 `tty_flip_buffer_push()` 用 `queue_work()` 排 CAF 的 `kthread_work`，
  編譯只有 `-Wincompatible-pointer-types` 警告（增量編譯時那個檔沒重編，根本沒看到），開機後藍牙 UART 觸發
  workqueue WARN。所以 `tools/142` 兩個分支各從頭編一次、比對警告集合
- ⚠ 衝突區與自動合併區互相依賴：`f_fs.c` 的 `mutex_lock` 自動合併進來、`mutex_unlock` 在衝突區（選 ours
  = adb 斷線就死鎖）；dwc3 的 `DWC3_EVENT_PENDING` 舊的清除位置被合併拿掉、新的在衝突區
- 保留本樹版本：f2fs（Android 回移的新版）、sdhci.c、tty_buffer.c、dvb dmxdev、arm64 proc.S

結果：enforcing 開機全功能正常。新增的 kernel WARN 只有 `/proc/driver/front_otp` 重複註冊（ASUS 相機驅動
註冊兩次；CIP 帶進上游「proc 名稱不准重複」的修補，第一個仍在）。

## 進度

| 步驟 | 狀態 |
|---|---|
| 建置環境（distro、記憶體、套件、repo）| ✅ 2026-09-25 |
| `repo sync` lineage-22.2 | ✅ 16 分鐘、115 GB、LFS 完整 |
| kernel 放進樹| ✅ `b0a1289a` |
| device tree 第一版（`tools/122` 骨架 + 改寫）| ✅ |
| build graph（`tools/124`）| ✅ rc=0 |
| 正式 blob 清單（ASUS + OnePlus）| ✅ build graph rc=0 |
| 設定檔換成 ASUS 的（音訊、media profiles、init rc、fstab、overlay、振動）| ✅ build graph rc=0 |
| sepolicy（照 16.0 的經驗整理，去掉 OnePlus 的）| 能開機之後 |
| 完整編譯、刷機 | ✅ 2026-09-25 開到桌面，見上面 1–11 |
| 參考 device tree（OnePlus msm8998-common / dumpling）| ✅ `~/ref/` |
| OnePlus 5 blob（TheMuppets）| ✅ `~/ref/` |
