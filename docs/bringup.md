# 建置與開機除錯報告

> **English summary** — Building LineageOS 16.0 and getting it to boot. Includes
> the root cause of seven build failures and six boot failures, each with the
> diagnostic that actually found it. Recurring themes: mismatches between `.rc`
> files and executables are completely silent at build time; `out/` is
> incremental, so removing a blob from the list does not remove the installed
> file; declaring a HAL in `manifest.xml` without a service registering it makes
> clients wait forever. Also covers the ADSP `-60` failure (OEM-fused image
> verification) that was the shared root cause of "no sound" and "no camera".
>
> *The body is in Traditional Chinese.*

日期：2026-09-22　　狀態：**編譯成功，尚未刷入手機**

```
lineage-16.0-20260922-UNOFFICIAL-Z01G.zip   666 MB
boot.img                                     15,843,328 bytes  (32 MB 分割的 47.2 %)
recovery.img                                 20,996,096 bytes  (32 MB 分割的 62.6 %)
```

產物放在輸出目錄（不進 git，校驗值另存 `SHA256SUMS`）。

---

## 環境

| 項目 | 值 |
|---|---|
| 原始碼 | LineageOS 16.0，709 個專案，67 GB，`~/lineage-16.0` |
| host | WSL2 Ubuntu 20.04.6，24 執行緒 / 31 GB RAM |
| Java | OpenJDK 1.8.0_452 |
| Python | **`python` → 2.7.18**、`python3` → 3.8.10 |
| ccache | 50 GB |
| repo sync | 13 分鐘 |
| 最後一次成功編譯 | 1 分 25 秒（增量；完整約 20 分鐘）|

---

## 七次失敗與修正

每一次都比前一次走得更遠。列出來是因為**大部分錯誤訊息都不指向真正的原因**。

### 1. `repo sync` — `Cannot initialize work tree`（0 %）
```
error.GitError: Cannot checkout LineageOS/android_external_chromium-webview_prebuilt_x86_64
```
手動 `git checkout` 才看到真因：`git-lfs filter-process --skip: git-lfs: not found`。
LineageOS 已把 chromium-webview 的 prebuilt APK 搬到 Git LFS。裝 `git-lfs 2.9.2` 解決。

諷刺的是最初寫 `repo init --git-lfs=false` 想繞過 LFS（而且那是布林旗標，給值會被拒），
正解是反過來要**裝**它。

### 2. `PRODUCT_BOOT_JARS += qcnvitems`（32 秒）
```
ninja: error: '.../JAVA_LIBRARIES/qcnvitems_intermediates/javalib.jar',
       needed by '.../dex_bootjars/system/framework/boot.prof', missing
```
這是**照 QTI 裝置慣例亂加**的結果。查證後：
- `qcnvitems.jar` 這台根本沒出貨（映像裡只有 `qcrilhook.jar`）
- `qcrilhook` 是靠 `etc/permissions/qcrilhook.xml` 宣告成 shared library，不是 boot jar
  ```xml
  <library name="com.qualcomm.qcrilhook" file="/system/framework/qcrilhook.jar"/>
  ```
- 參考機的 `PRODUCT_BOOT_JARS` 放的是 `telephony-ext` / `WfdCommon` / `org.ifaa.android.manager`

整段移除。

### 3. `python` 指向 python3（318 / 93517）
```
build/make/tools/normalize_path.py:25:  print os.path.normpath(p)
build/make/tools/merge-event-log-tags.py:51:  except getopt.GetoptError, err:
libcore/annotations/generate_annotated_java_files.py:34:  print '...'
                                                          ^ SyntaxError
```
AOSP 9 的建置腳本是 **Python 2**，且用 `#!/usr/bin/env python` 呼叫。
環境設定時裝成 `python-is-python3` 是錯的，要 `python-is-python2`。

這也再次說明為什麼選 Ubuntu 20.04 —— 新版 Ubuntu 連 `python-is-python2` 這個套件都沒有。

### 4. `bdroid_buildcfg.h` 不存在（14.5 分鐘）
```
system/bt/internal_include/bt_target.h:33:10: fatal error: 'bdroid_buildcfg.h' file not found
```
`BoardConfig.mk` 的 `BOARD_BLUETOOTH_BDROID_BUILDCFG_INCLUDE_DIR` 指向空目錄。
依本機參數補上（`qcom.bluetooth.soc=cherokee` / WCN3990、
`a2dp_offload_cap=sbc-aptx-aptxhd-aac`），不是照抄參考機。

### 5. webview APK 是 LFS 指標檔（50 %，14726 / 29333）
```
java.util.zip.ZipException: zip END header not found
```
`external/chromium-webview/prebuilt/arm64/webview.apk` 只有 **134 bytes**：
```
version https://git-lfs.github.com/spec/v1
oid sha256:446ead71292578830d99e690fd8dded73bc63d85df80f0cfba37762ccb330326
size 243509357
```
**`repo sync` 成功不等於 LFS 內容到位。** 裝 git-lfs 只是讓 `git checkout` 不報錯，
實際大檔仍是指標。要另外在各 LFS repo 跑 `git lfs pull`（4 個 APK 共約 770 MB）。

已把檢查併進 `tools/15_repo_sync.sh` 尾端，下次重建環境會自動處理。

> 附帶一個自己的 bug：第一版掃描用 `find -size -1k` 找指標檔，回報 0 個。
> `find -size` 的單位是 1K 區塊且**無條件進位**，134 bytes 算 1 個區塊，
> `-1k`（小於 1）只會匹配 0 byte 的檔案。要用 `-size -4096c`。

### 6. python3 那次留下的污染產物（4 %）
```
FAILED: .../apache-xml_intermediates/dex-hiddenapi/classes.dex
hiddenapi E ... No DEX files specified
```
**這次最值得記。** 因果鏈：

AOSP 這樣產生 Java 原始檔清單：
```
... | build/make/tools/normalize_path.py > java-source-list
```
python3 跑這支 Python 2 腳本會 SyntaxError，**但 shell 的重導向已經把檔案建出來了**（0 bytes），
而整條規則的結束碼被後面的命令蓋掉 → ninja 認為這個目標完成。

結果 `classes.jar` 從零個原始檔編出來（18 KB），dex 階段沒有輸入，
一直要到 `hiddenapi` 才報「No DEX files specified」。

**而且把 python 改對之後 ninja 也不會重做** —— 那些目標「看起來是最新的」。
所以症狀在根因修好後仍然復發。

153 個 `java-source-list` 中只有 3 個被污染，針對性刪除對應的 `_intermediates` 即可
（`tools/24_clean_poisoned.sh`），不必砍掉 2.7 GB 的 `out/target/common`。

### 7. `fstab.qcom` 缺 `/boot`（最後打包階段）
```python
File "build/make/tools/releasetools/common.py", line 852, in CheckSize
    p = info_dict["fstab"][mount_point]
KeyError: '/boot'
```
執行期 fstab 確實不需要 `/boot` 與 `/recovery`（`emmc` + `defaults` 不會被 fs_mgr 掛載），
但 **releasetools 要靠它們查分割區大小**。
同機種的 `shakalaca/android_device_asus_Z01G/recovery.fstab` 其實就有這兩條，是漏抄了。

---

## 產物驗證

```
zip 完整性        OK（11 個項目，signed by SignApk）
boot.img          15,843,328 / 33,554,432  (47.2 %)  OK
recovery.img      20,996,096 / 33,554,432  (62.6 %)  OK
```

### boot.img header — 與原廠完全一致
```
page_size      4096        header_version 0
kernel_addr    0x8000      ramdisk_addr   0x1000000
second_addr    0xf00000    tags_addr      0x100
os_version     9.0.0       os_patch_level 2022-01
```
`BOARD_KERNEL_BASE := 0x00000000` 有效 —— offset 全部對上從原廠 boot 讀到的值。

### boot.img 裡的 kernel — 與獨立編出來的那顆相同
```
Linux version 4.4.78-perf+ (builder@buildhost) (gcc version 4.9.x 20150123 (prerelease) (GCC) )
kernel blob    13,929,714 bytes
解壓後         37,318,712 bytes   <- 與獨立編出來的「完全相同」
附加 DTB       3 個，大小與原廠逐一相符
               MSM 8998 v2.1 MTP  380,735  msm-id (292, 0x00020001)  <- 本機用這顆
               MSM HAMSTER RUMI   312,955  msm-id (306, 0x00000000)
               MSM 8998 v1 MTP    363,321  msm-id (292, 0x00000000)
```
AOSP 的 build 系統從 `kernel/asus/msm8998` 重新編出來的 kernel，
解壓後大小與手動編的**一模一樣**（37,318,712 bytes）。

---

## 尚未處理 / 刷機前要知道的

這是**第一次編出來的版本，還沒開機驗證過**。以下都還是空的或缺的：

| 項目 | 狀態 | 影響 |
|---|---|---|
| `sepolicy/` | 空 | SELinux 沒有裝置專屬規則，預期大量 denial |
| `overlay/` | 空 | framework 設定全用預設值（電信、電池、顯示等）|
| `configs/` | 空 | audio_policy / media_codecs / thermal / gps 設定沒帶進來 |
| init rc | 無 | ASUS 的 `init.asus.*.rc` 沒有整合 |
| kernel 的 qcacld | 無 | **Wi-Fi 預期不會動** —— ASUS GPL 原始碼不含 WLAN 驅動 |
| 自編 recovery | 未測 | 刷 zip 要用 TWRP，不是這個 recovery.img |

`m nothing` 剩下 2 個 `overriding commands` 警告是刻意的（blob 覆蓋原始碼）：
`android.hardware.biometrics.fingerprint@2.1-service`、`vendor/etc/wifi/wpa_supplicant.conf`。

**第一次開機卡在 logo 是常態。** 但 [kernel.md](kernel.md) 已經證明這顆 kernel 能在本機開機，
所以除錯時可以排除 kernel 這個變因，專心查 device tree 與 blobs。

---

# 第一次刷入失敗的除錯（2026-09-22 晚間）

刷入後症狀：**亮完 ASUS logo 就黑屏，機身溫熱，adb / fastboot 完全看不到手機**
（Windows 只看到 `未知的 USB 裝置（要求裝置描述元失敗）` `VID_0000&PID_0002`）。

## 取得證據的過程

**TWRP 的 adb 不能用**，這是個硬限制：
- `setprop sys.usb.config adb` 無效 —— 這台 cmdline 有 `androidboot.configfs=true`，
  USB gadget 要靠 init rc 的觸發規則去 configfs 組裝，光設屬性不觸發任何動作
- 同機種的 TWRP 樹有 `TW_EXCLUDE_DEFAULT_USB_INIT := true`，代表它依賴裝置自己的
  USB init，而那份 init 不在 TWRP 的 ramdisk 裡

所以改用 **TWRP 終端機把 log 複製到外接 SD 卡，再用讀卡機讀**。
（TWRP 終端機的 `setprop` 是可用的 —— 稍早正是靠它補上 `ro.product.device` 才刷得進去。）

## 三個發現

### 1. 沒有 kernel panic
`/proc/last_kmsg` 不存在、`/sys/fs/pstore/` 是空的。
→ kernel 沒事，與 [kernel.md](kernel.md)「自編 kernel 能開機」的結論一致，問題全在 userspace。

### 2. `/data` 從來沒被 Format
`/data/tombstones/*` 全部是
`Build fingerprint: 'asus/WW_Z01GD/ASUS_Z01GD_1:8.0.0/...'`，
程序是 `com.asus.mobilemanager`、`com.google.android.youtube` ——
**全是原廠 Oreo 的，沒有任何一個來自 LineageOS 開機**。

`recovery.log` 也寫著：
```
I:Device is encrypted with the default password, attempting to decrypt.
Data successfully decrypted, new block device: '/dev/block/dm-0'
```
→ `/data` 仍是 Oreo 的 FDE 加密資料。LineageOS 解不開，必定開不了機。

### 3. `fstab.qcom` 根本沒被安裝進 ramdisk（真正的致命原因）
把自編 `boot.img` 與原廠的 ramdisk 攤開比對：

| | LineageOS 自編 | 原廠 Oreo |
|---|---|---|
| `vendor -> /system/vendor` | 有 | 有 |
| **`fstab.qcom`** | **沒有** | 沒有（原廠靠 cmdline 的 dm-verity 掛 system）|
| `init.asus.rc` | 沒有 | 43 KB |

`device.mk` 裡寫了 `PRODUCT_PACKAGES += fstab.qcom`，但**從來沒有定義這個模組**
（`rootdir/` 底下沒有 `Android.mk`），而 build 不會因為模組不存在而報錯。

後果：Android 9 的 first-stage init 靠 `/fstab.${ro.hardware}` 掛載 `/system`，
ramdisk 裡沒有 → `/system` 掛不起來 → init 立刻死。
這完全解釋了「黑屏 + USB 完全不列舉 + `/data` 裡沒有任何 LineageOS 產生的檔案」——
根本走不到設定 USB gadget 那一步。

修法：新增 `device/asus/Z01G/rootdir/Android.mk`，
用 `LOCAL_MODULE_PATH := $(TARGET_ROOT_OUT)` 把 fstab 裝進 ramdisk 根目錄。

## 連帶修正：blob 清單從根本上重做

`tools/30_gap_check_full.sh` 不做任何「哪些重要」的預判，直接全列出來對照，結果：

| 區塊 | 缺 / 總數 |
|---|---|
| `vendor/etc/init` | **28 / 38**（含 `init.qcom.rc`、`init.target.rc`、`rild.rc`）|
| `vendor/etc` | 231 / 444 |
| `vendor/bin` | **189 / 238** |
| `etc/permissions` | 63 / 77 |
| `vendor/firmware` | 63 / 113 |

少了 `init.qcom.rc`，就算 `/system` 掛起來也不會有任何 qcom HAL 啟動。

**原本的方法（參考機交集 + 關鍵字掃描）對非 Treble 移植是錯的。**
正確做法是反過來：`/system/vendor` 整個帶走，再扣掉 LineageOS 自己會編的。
改用 `tools/31_build_blob_list.py` 後為 **3337 條**（原 1352 條）。

同時從 `device.mk` 移除 51 個與 blob 重複的 AOSP HAL 模組
（`tools/32_prune_device_mk.py`）—— 對這種舊機移植，原廠的 vendor HAL
才是跟硬體對得上的那份。

> 剩下 204 個 `overriding commands for target` 警告是預期的：
> 那些 HAL service 由 LineageOS 上游繼承的 product makefile 拉進來，
> 從 `device.mk` 移除擋不住。結果是 `PRODUCT_COPY_FILES`（blob）覆蓋模組規則，
> 也就是原廠 vendor HAL 勝出 —— 正是我們要的。

## 自己引入的三個 bug（都已修並在對應腳本註明）

1. **`find -size -1k` 只匹配 0 byte 檔案** ——
   單位是 1K 區塊且無條件進位，134 bytes 的 LFS 指標檔算 1 個區塊。
   要用 `-size -4096c`。第一版掃出 0 個，差點誤判「LFS 沒問題」。

2. **python 文字模式寫檔在 Windows 上產生 CRLF** ——
   把 `device.mk` 變成全 CRLF。Makefile 變 CRLF 後，續行的 `\r` 會混進模組名稱，
   每個模組名後面多一個 `\r`，比對不到任何真實模組而被**靜默丟棄**。
   一律 `open(..., newline='\n')`。

3. **`os.walk` 會把「指向檔案的 symlink」放進 files 清單** ——
   不像 `find -type f` 會排除。清單因此多了 199 條 symlink
   （148 個是 `vendor/bin/*` → `toybox_vendor`）。
   `extract-files.sh` 抽不到它們只印訊息不會失敗，一直到編譯才炸：
   `ninja: error: '...wcd9320_anc.bin', missing and no known rule to make it`。
   新增 `tools/33_check_extract.sh` 在抽完後檢查完整性。

## 下次刷入的正確順序

1. Wipe → **Format Data** → 輸入 `yes`　← **上次漏掉的就是這步**
2. Wipe → Advanced Wipe → Dalvik / Cache / System
3. Advanced → Terminal → `setprop ro.product.device Z01G`
4. Install → Micro SDCard → zip

---

# 第三輪：開到開機動畫，但 system_server 永遠起不來

（log 來源：`_docs/dbg3/`，由 `rootdir/etc/init.z01g-debug.rc` 的服務寫到 `/data`）

第二輪補上 `android.hidl.base@1.0.so` / `android.hidl.manager@1.0.so` 之後，
zygote 起來了、surfaceflinger 起來了、dex2oat 跑完了、**開機動畫在動**，
但動畫播了 27 分鐘沒有結束。

## 根因：audio HAL 服務從頭到尾沒被啟動

順著等待鏈往回推：

```
ServiceManager:     Waiting for service 'media.audio_flinger' on '/dev/binder'...   ×7929  (pid 1278)
AudioSystem:        AudioFlinger not published, waiting...                          ×158
ServiceManagement:  Waited one second for android.hardware.audio@2.0::IDevicesFactory/default.
                    Waiting another...                                              ×873   (pid 789)
init:               Could not find service hosting interface
                    android.hardware.audio@2.0::IDevicesFactory/default
```

`AudioFlinger` 的建構子會先 `IDevicesFactory::getService()`，這一等就是 873 秒；
沒有回來就不會註冊 `media.audio_flinger`，system_server 的 AudioService 因此卡住，
開機動畫永遠不會結束。

再往下查 —— 執行檔明明在：

```
out/.../system/vendor/bin/hw/android.hardware.audio@2.0-service   20256 bytes（= 原廠）
out/.../system/vendor/etc/init/                                   沒有 android.hardware.audio@2.0-service.rc
```

`.rc` 被 `tools/31_build_blob_list.py` 的 `EXCLUDE_PATTERNS` 排掉了。
當初排它的理由是「這些 HAL 用 AOSP 版，AOSP 模組會自帶 .rc」，
但後來 `tools/32_prune_device_mk.py` 又把那些 AOSP 套件從 `device.mk` 移除，
**兩個決定對不起來**：blob 提供執行檔、AOSP 提供 .rc，結果兩邊都只到一半。

> 「執行檔在、服務定義不在」與「服務定義在、執行檔不在」在編譯期完全不會報錯，
> 只會在開機時安靜地卡住。新增 `tools/40_check_services.sh` 做這個交叉比對，
> 每次改完 blob 清單都要跑。

實際處置：audio 改成完整用 AOSP 版（service + impl + effect impl）。
理由是原廠那兩個檔的 `DT_NEEDED` 全是 AOSP 函式庫、沒有任何 QTI 擴充，
等於本來就是 AOSP 版；真正的硬體實作在 `vendor/lib*/hw/audio.primary.msm8998.so`，
那個照收。

## 四個無限重啟的 vendor service：Oreo 執行檔 + Pie 函式庫

init 每 5 秒重啟一輪，各重啟了 325 次：

| 服務 | 錯誤 | 判讀 | 處置 |
|---|---|---|---|
| `vendor.wifi_hal_legacy` | 缺 `android::wifi_system::InterfaceTool` 的 vtable | Pie 的 `libwifi-system.so`（68384）蓋掉原廠（48184），版面不同 | 改用 AOSP 的 service |
| `vendor.media.omx` | 缺 `OmxStore` 無參數建構子 | Pie 的 `libstagefright_omx.so` 把建構子改成有參數 | 改用 AOSP 的 service |
| `vendor.keymaster-3-0` | `dlopen ...keymaster@3.0-impl.so` 缺 `SoftKeymasterContext::ParseKeyBlob` | 符號在 `libsoftkeymasterdevice.so`，我們裝的是 Pie 版（287024 vs 原廠 143888） | 改用 AOSP 的 service + impl |
| `nqnfc_hal_service` | abort：`Error while registering nfc AOSP service: 1` | passthrough 找不到 `android.hardware.nfc@1.0-impl` | bring-up 先關 |

keymaster 這個**不能用「換回 Oreo 函式庫」解決**：
`/system/bin/keystore`（Pie）也連結 `libsoftkeymasterdevice.so`，
換成 Oreo 版會換掉 keystore 的腳。

另外 `wfdservice`（缺 `libskia.so`，Pie 不再安裝成共享函式庫）與
`qti_gnss_service`（`vendor.qti.gnss@1.0_vendor.so` 需要 Oreo HIDL 產生的
`gnss@1.0 toString<GnssNiNotifyFlags>` 模板實體）一併關掉。

## USB / adb 為什麼永遠連不上

一開始以為是這兩行：

```
init: Command 'mount configfs none /config' ... failed: Device or resource busy
init: Command 'write .../strings/0x409/serialnumber ${ro.serialno}' ... cannot expand
```

**兩個都無害。** configfs 是 AOSP 的 init.rc 已經掛過；
`ro.serialno` 是空的是因為這台的 bootloader 不傳 `androidboot.serialno`
（實測 cmdline 裡確實沒有），原廠 Oreo 也一樣，init 只會跳過那一行。

真正的原因在 `/default.prop`：

```
persist.sys.usb.config=none
```

來自 `build/make/tools/post_process_props.py` 的 fallback ——
沒有人指定值時就填 `none`。開機時：

```
init: processing action (persist.sys.usb.config=* && boot) from (/init.usb.rc:102)
        -> setprop sys.usb.config none
init: processing action (sys.usb.config=none && sys.usb.configfs=1) from (/init.usb.configfs.rc:1)
        -> write /config/usb_gadget/g1/UDC none    失敗：No such device
```

gadget 從頭到尾沒被綁定，所以 USB 根本不列舉。

修法：`device.mk` 加 `PRODUCT_DEFAULT_PROPERTY_OVERRIDES += persist.sys.usb.config=adb`，
並在 `tools/22_build.sh` 加 `export WITH_ADB_INSECURE=true`
（否則 `ro.adb.secure=1`，adbd 會要求在畫面上按「允許 USB 偵錯」，
而現在還沒有畫面可以按）。**能正常開機後要拿掉。**

## log 只涵蓋最後 15 分鐘的原因

`adsprpcd` 每 25ms 重啟一次並印 4 行：22.6 萬行裡 20.3 萬行是它（90%），
12 分鐘就寫滿 `-r 8192 -n 4` 的 40MB 配額。
而且 `z01g-logcat` 這個服務本身 exit(1) 了 121 次，每次重啟都重開檔案。

除錯 rc 已改成：`sh -c "... >> file"`（append，重啟不清空）、
把 `/system/vendor/bin/adsprpcd` 這個 tag 設成 `S`、
明確指定 buffer（`-b all` 含 security buffer，權限不對會直接 exit），
並加上每 15 秒一次的 `getprop` + `ps` 快照。

## 待解：ADSP firmware 載不起來（不擋開機，但沒有聲音）

```
subsys-pil-tz 17300000.qcom,lpass: adsp: loading from 0x8b200000 to 0x8cc00000
scm_call failed: func id 0x42000201, ret: -60, syscall returns: 0x0, 0x0, 0x0
subsys-pil-tz 17300000.qcom,lpass: adsp: Initializing image failed(rc:-22)
adsp-loader: adsp_load_fw: pil get failed,
adsp-loader: adsp_load_fw: Q6 image loading failed
```

func id `0x42000201` = `SCM_SVC_PIL` / `PAS_INIT_IMAGE_CMD`，
也就是 TZ 拒絕了 ADSP 的映像初始化。只試了一次就放棄。
同樣走 PAS 的 `ipa_fws.mdt` 載入成功，所以 TZ 本身是通的。
`adsprpcd` 的 `apps_dev_init failed, errno Operation not permitted` 是這個的連帶結果。
開機通了之後再追。

---

# 第四輪：system_server 每 126 秒被砍一次

（log 在 `_docs/dbg4/`。這輪 USB 終於會列舉了，但 adb 一直 offline —— 因為
adbd 活著、system_server 卻反覆重生，host 的 CNXN 握手接不上。）

## 這輪修對的東西

| 項目 | 結果 |
|---|---|
| audio HAL 服務 | ✅ `audioserver` + `android.hardware.audio@2.0-service` 都起來了 |
| USB gadget | ✅ 會列舉（序號 `111111111111111`，ASUS `init.asus.usb_ssn.sh` 的 fallback）|
| 11 個 HAL 的 .rc | ✅ light / power / thermal / sensors / vibrator / graphics.* / health / gatekeeper / memtrack 全部有服務在跑 |
| system_server | ✅ 有起來（前幾輪根本沒出現）|
| 開機完成 | ❌ 每 126 秒整個循環一次 |

## 診斷過程

`z01g-snap.txt`（每 15 秒一次 `ps`）把週期性看得一清二楚：

```
 #  時間      system_server  zygote64  bootanim  surfaceflinger  audioserver
 2  15:19:02       2265         660      1187        803           801
10  15:21:03       6111        3417      1187        803          3419
18  15:23:04       7819        5343      1187        803          5345
26  15:25:05      10614        8246      1187        803          8250
34  15:27:06      15397       12309      1187        803         12311
```

`bootanimation` 與 `surfaceflinger` 的 pid 完全不變，其餘全部每 126 秒換一輪 ——
`zygote` rc 的 `onrestart restart audioserver / cameraserver / media / netd / wificond`
正好對得上。

kmsg：
```
init: Service 'zygote' (pid 660) received signal 9
binder: release 2265:6002 transaction 2975 out, still active
```
zygote 收到 SIGKILL 是**自己殺自己**——`com_android_internal_os_Zygote.cpp` 的
`SigChldHandler()` 發現 system_server 終止時會 `kill(getpid(), SIGKILL)`。
所以真正死的是 system_server。

沒有 tombstone（signal 6 的那批是 audioserver）、`/data/anr` 空的、
kmsg 也沒有 SysRq 輸出（Watchdog 殺之前會 `doSysRq('w')`，而這顆 kernel
`CONFIG_MAGIC_SYSRQ=y`，真是 Watchdog 一定看得到）—— 所以不是 Watchdog、不是原生崩潰。

答案在 `/data/system/dropbox`：**6 個 `system_server_crash`**，剛好對上 6 次重啟。

## 根因：Android 9 的 privapp 權限白名單

```
java.lang.IllegalStateException: Signature|privileged permissions not in
privapp-permissions whitelist: {
    com.quicinc.cne.CNEService:  android.permission.INTERACT_ACROSS_USERS,
    com.qualcomm.qcrilmsgtunnel: android.permission.INTERACT_ACROSS_USERS,
    com.qualcomm.location:       android.permission.CONTROL_LOCATION_UPDATES,
    com.quicinc.cne.CNEService:  android.permission.PACKET_KEEPALIVE_OFFLOAD }
    at PermissionManagerService.systemReady(PermissionManagerService.java:2123)
    at PackageManagerService.systemReady(PackageManagerService.java:21662)
    at SystemServer.startOtherServices(SystemServer.java:1756)
```

Android 9 把 `ro.control_privapp_permissions` 預設改成 `enforce`：
`/system/priv-app` 底下每個 app 用到的 `signature|privileged` 權限都必須列在
白名單 XML 裡，少一條就直接丟例外。Oreo 預設是 `log`（只記錄不擋），
所以 ASUS 的 blob 從來沒帶過這個檔。

修法：拿 `LineageOS/android_device_oneplus_msm8998-common` 的
`privapp-permissions-qti.xml` 當底，補上 `com.qualcomm.location` 的
`CONTROL_LOCATION_UPDATES`（參考樹只列了 `MANAGE_USERS`），
裝到 `/system/etc/permissions/`（這三個 app 都在 `/system/priv-app`，
`PermissionManagerService` 對非 vendor 的 app 只查那裡）。

> 這種錯誤 dropbox 會一次列出**全部**缺的權限，所以補完這四條就不會再有下一輪。

## 同時發現、但不擋開機的問題

**audioserver 每 ~60 秒 SIGABRT**（tombstone_24～30）：
```
pid: 5986, tid: 17988, name: TimeCheckThread  >>> /system/bin/audioserver <<<
Abort message: 'TimeCheck timeout for IAudioFlinger: 22'
  #02 pc 0000e2ef  /system/lib/libmedia_helper.so
       (android::TimeCheck::TimeCheckThread::threadLoop()+270)
```
AudioFlinger 的 5 秒看門狗，binder 呼叫卡住 —— ADSP 載不起來的下游效應。

**`z01g-logcat` exited with status 127 ×172**：我把服務包成
`sh -c "logcat ..."`，但 `/vendor/bin/sh` 的預設 PATH 沒有 `/system/bin`，
整份 logcat 只有 11 KB 全是 `logcat: not found`。改成絕對路徑。
（再上一版是直接把 `/system/bin/logcat` 當服務執行檔，所以沒踩到。）

**`init: Command 'restart audio-hal-2-0' ... failed: service audio-hal-2-0 not found`**：
AOSP 的 `audioserver.rc` 寫 `onrestart restart audio-hal-2-0`，
但服務實際叫 `vendor.audio-hal-2-0`。純粹是訊息難看，init 本來就會連
process group 一起殺，不影響行為。

---

# 第五輪：privapp 修掉了，換 Watchdog 殺 system_server

（log 在 `_docs/dbg5/`）

`/data/system/dropbox` 這次**沒有** `system_server_crash` —— privapp 修對了。
但 `z01g-snap.txt` 顯示整組還是每 150～190 秒重來一次，而且這次 kmsg 裡出現了
上一輪沒有的東西：

```
(CPU:7-pid:19774:watchdog) sysrq: SysRq : Show Blocked State
(CPU:7-pid:19774:watchdog) sysrq: SysRq : Show backtrace of all active CPUs
```

是 Watchdog。logcat（這輪終於抓到了）直接給出答案：

```
W Watchdog: *** WATCHDOG KILLING SYSTEM PROCESS: Blocked in handler on main thread (main)
W Watchdog:     at com.android.server.location.GnssLocationProvider.class_init_native(Native Method)
W Watchdog:     at com.android.server.location.GnssLocationProvider.<clinit>(GnssLocationProvider.java:2716)
W Watchdog:     at com.android.server.LocationManagerService.loadProvidersLocked(LocationManagerService.java:600)
W Watchdog:     at com.android.server.LocationManagerService.systemRunning(LocationManagerService.java:349)
W Watchdog:     at com.android.server.am.ActivityManagerService.systemReady(ActivityManagerService.java:15503)
W Watchdog: *** GOODBYE!
```

`GnssLocationProvider` 的 static initializer 裡是 `IGnss::getService()`，
會一直等。logcat 裡 `Waited one second for android.hardware.gnss@1.0::IGnss/default`
出現 367 次（其餘所有 HAL 加起來只有 4 次）。

## 根因：manifest 宣告了、服務卻被停用

非 Treble（`ro.treble.enabled=false`）的 `getService()` 行為差別很大：

| manifest | `getTransport()` | 行為 |
|---|---|---|
| 有宣告 | `HWBINDER` | **無限重試**，每秒印一次 `Waiting another...` |
| 沒宣告 | `EMPTY` -> legacy | 試一次 hwbinder，然後轉 passthrough：dlopen `<interface>-impl*.so`，沒有就回 null |

上一輪我把 `qti_gnss_service` 停掉（它因為 Oreo/Pie symbol 不相容 crash loop），
卻沒有同步把 `android.hardware.gnss` 從 manifest 拿掉 —— 於是變成「宣告了但沒人註冊」。

> 這不是停用 GNSS 造成的新問題：上一輪 GNSS 服務也是 crash loop、同樣沒註冊，
> 只是 system_server 在更早的 `PackageManagerService.systemReady()`（第 1756 行）
> 就被 privapp 例外殺掉，根本走不到第 1810 行的 `ActivityManagerService.systemReady()`。

修法：把 `android.hardware.gnss` 從 manifest 移除，改走 passthrough。
先驗證過 `/vendor/lib64/hw/android.hardware.gnss@1.0-impl-qti.so` 的 171 個符號
全部解得開，而且**不需要**那個害 QTI 服務掛掉的
`toString<IGnssNiCallback::GnssNiNotifyFlags>`（只有 `vendor.qti.gnss@1.0_vendor.so` 需要）。
所以 GNSS 很可能真的能用，只是跑在 system_server 行程內。

> **後來實測：確實能用。** 一度以為 GPS 壞了，其實只是定位開關從來沒開過
> （`location_providers_allowed` 是空的）。打開後 `loc_eng init`、capabilities 回報，
> GPSTest 收得到 GPS / GLONASS / 北斗 / Galileo / QZSS，81 次定位、失敗率 0%，
> 平均精度約 8 m。
>
> 兩個看起來像錯誤、其實不是的：
> `Unable to initialize GNSS Xtra interface` —— `gnss@1.0-impl-qti.so` 裡完全沒有
> Xtra 的符號，QTI 的星曆下載由 `xtra-daemon` 自己做；
> `dumpsys location` 的衛星表全部「未知」、時間 2017-01-01 —— HAL 的
> `getDebugData()` 只回填樣板。
>
> 教訓：**「停用了 X 的服務」不等於「X 不能用」。** 同一個功能常有標準路徑與
> vendor 擴充兩條，要分開驗，而且要用功能本身驗（開 App 看衛星），
> 不是用「我記得當時關掉了」。

同時移除其他已停用服務的 manifest 條目：`vendor.qti.gnss`、`android.hardware.nfc`、
`vendor.nxp.hardware.nfc`、`com.qualcomm.qti.wifidisplayhal`，
並把原廠的 `vendor/manifest.xml` blob 一併排除（舊路徑，內容與我們的不一致，只會誤導）。

## adb 永遠 offline 的根因：kernel 沒開 CONFIG_AIO

USB 會列舉（`adb devices` 看得到序號 `111111111111111`）但永遠 offline。
logcat 裡 adbd 每秒刷上千行：

```
I adbd: registering usb transport
I adbd: initializing functionfs
I adbd: functionfs successfully initialized
E adbd: aio: got error submitting read: Function not implemented
E adbd: remote usb: read terminated (message): Function not implemented
I adbd: closing functionfs transport
```

`Function not implemented` = `io_submit()` 回 ENOSYS。
Android 9 的 adbd 走 `USB_FFS_AIO` 讀寫 USB 端點，而 ASUS 的 defconfig 是
`# CONFIG_AIO is not set` —— 出貨 kernel 的 `/proc/config.gz` 也一樣
（upstream 預設是 y，關掉省 7 KB）。descriptor 寫得進去所以會列舉，
但一筆資料都讀不到，host 端就卡在 offline。Oreo 的 adbd 不走 AIO，所以原廠不受影響。

修法：`tools/51_patch_kernel_aio.sh` 把 defconfig 改成 `CONFIG_AIO=y`，
在 kernel 的 git repo 裡 commit 保留 patch，再複製到 AOSP 樹
（`16_place_trees.sh` 用 `cp -al` 硬連結，`sed -i` 會斷開連結）。

## `/vendor/rfs` 整棵樹從來沒被抽出來

logcat 20 MB 取樣裡 `tftp_server` 佔 16 萬行（logcat 18 分鐘漲到 **1.5 GB** 的主因）：

```
tftp-server : mkdir failed: [/vendor/rfs/msm/mpss/readwrite] [No such file or directory]
tftp-server : mkdir failed: [/vendor/rfs] [Read-only file system]
```

`/vendor/rfs` 是 25 個目錄 + 45 條 symlink，**一個一般檔案都沒有**：
`tools/31_build_blob_list.py` 會跳過 symlink，空目錄本來就不在檔案清單裡，
所以整棵樹從頭到尾沒被收進來。rfs 是 modem / adsp / slpi 讀寫 EFS 類檔案的路徑。

修法：`tools/52_gen_rfs_mk.py` 從原廠映像產生 `rootdir/rfs.mk`，
用 `LOCAL_POST_INSTALL_CMD` 建目錄與 symlink
（`PRODUCT_COPY_FILES` 做不到 symlink，blob 清單也抽不到）。

---

# 第六輪：**開機完成**（2026-09-23 00:28）

```
sys.boot_completed = 1      uptime 144 秒      bootanim=stopped
16.0-20260922-UNOFFICIAL-Z01G   Android 9 / SDK 28
kernel 4.4.78-perf+ (builder@buildhost)   自編那一顆 + CONFIG_AIO
```

## adb 在開機 14 秒就上線了

`CONFIG_AIO=y` 正是答案。之前「USB 列舉得出來但永遠 offline」完全是
Pie 的 adbd 用 `io_submit()` 而 kernel 沒開 AIO 造成的。
這一改之後除錯方式整個不同：不用再進 TWRP 唯讀掛 `/data` 撈檔案，
開機動畫還在跑就能 `adb logcat` 看即時狀況。

## 開機當下的狀態

| 項目 | 狀態 |
|---|---|
| 顯示 | ✅ 1080x1920 @60Hz，density 480（**不是 2160**，BoardConfig 原本寫錯）|
| 觸控 | ✅ `focal-touchscreen` |
| 指紋 | ✅ 裝置節點在（`goodixfp`）|
| 感測器 | ✅ ICM20690 加速度/陀螺、AK09918 磁力計等 |
| 電池 | ✅ level 100 / temp 34.0°C / health good |
| 分割區 | ✅ /data /cache /system /persist /firmware /dsp 全掛好 |
| 子系統 | ✅ modem / slpi / venus / ipa_fws / spss / a540_zap 全 ONLINE |
| ADSP | ❌ `OFFLINING`，`/proc/asound/cards` = no soundcards |
| Wi-Fi | ❌ 沒有 wlan0（kernel 缺 qcacld，預期內）|

## 開機兩分鐘後又被打掉：com.qualcomm.location

```
FATAL EXCEPTION IN SYSTEM PROCESS: main
java.lang.UnsatisfiedLinkError: dlopen failed: cannot locate symbol
  "..._ZN7android8hardware4gnss4V1_08toStringINS2_15IGnssNiCallback17GnssNiNotifyFlags..."
  referenced by "/system/lib64/vendor.qti.gnss@1.0.so"
    at com.qualcomm.location.izatprovider.IzatProvider.<clinit>(IzatProvider.java:591)
    at com.qualcomm.location.izatprovider.NetworkLocationService.onCreate(...:42)
    at com.android.server.SystemServer.run(SystemServer.java:476)
```

`com.qualcomm.location` 的 `NetworkLocationService` 在它自己的 manifest 裡是
`android:process="system"`，也就是跑在 **system_server 行程內**。
它的 static initializer 去 `System.loadLibrary` 載 `vendor.qti.gnss@1.0.so`，
而那支需要的正是害 QTI GNSS 服務掛掉的同一個 Oreo 專屬 symbol。

> 同一個 symbol 這一輪出現了三次、三個不同層面：
> ① `vendor.qti.gnss@1.0-service` 連結失敗（crash loop）
> ② 停用它之後 manifest 沒同步 -> `IGnss::getService()` 卡死 -> Watchdog
> ③ `com.qualcomm.location` 在 system_server 內 dlopen 同一支 .so -> UnsatisfiedLinkError

修法：把 `priv-app/com.qualcomm.location` 連同 `izat.xt.srv.jar` 與兩個
permissions xml 一起移出 blob 清單。不影響 GPS 本身 ——
衛星定位走 framework 的 `GnssLocationProvider` 直接對
`android.hardware.gnss@1.0-impl-qti.so`（passthrough），跟 Izat 無關。

## 待解

**ADSP 載不起來**（`subsys4: adsp state=OFFLINING`，其餘子系統全 ONLINE）：
`/firmware/image/adsp.mdt`（7260 bytes）與 `adsp.b00` 都在，
device tree 的 `qcom,firmware-name` = `adsp` 也對，
而同樣走 PAS 的 modem / venus / slpi 全部成功 —— 所以 TZ 的 PAS 機制沒問題，
單獨是 ADSP 這顆映像被拒絕（`scm_call failed: func id 0x42000201, ret: -60`）。
連帶 `audioserver` 每 60 秒 `TimeCheck timeout for IAudioFlinger` SIGABRT。

下一步實驗：取得 root（Settings -> 開發者選項 -> Root access -> ADB）後
`echo 1 > /sys/kernel/boot_adsp/boot` 手動再觸發一次，看是不是開機早期
（8.5 秒，剛掛上 /firmware）的時序問題。

---

# Wi-Fi：原廠模組完全不能用，必須自己編 qcacld

## 起點：一個被推翻的假設

我在建置 log 裡看到 `Copy: .../vendor/lib/modules/qca_cld3_wlan.ko`，一度以為
「Wi-Fi 驅動已經在 image 裡，說不定 insmod 就能用」。**這個猜想是錯的**，
兩個層面都不成立。

### 1. 那顆 .ko 根本沒進最終 image

```
out 裡的  msm_11ad_proxy.ko  40624 bytes
抽出來的 blob                43894 bytes     ← 大小不一樣
```
out 裡的 `.ko` **是我們自己的 kernel 編出來的**。kernel 的模組安裝步驟會把
`$(TARGET_OUT_VENDOR)/lib/modules/` 整個換掉，blob 複製進去的會被蓋掉。
而 qcacld 不在 ASUS 的 kernel 原始碼裡，所以就空缺了。

### 2. 就算放進去也載不了 —— CRC 不合

`CONFIG_MODULE_SIG_FORCE=y`（強制驗簽）只是第一道關卡，關掉就好。
真正的問題是 `modversions`：模組用到的每個核心匯出符號都帶 CRC，
載入時必須完全相符。`tools/71_ko_crc_check.py` 離線比對
（讀 `.ko` 的 `__versions` 區段 vs kernel 的 `Module.symvers`）：

| 模組 | 相符 | 缺 | CRC 不合 |
|---|---|---|---|
| `qca_cld3_wlan.ko` | 211 | 0 | **169** |
| `wil6210.ko` | 93 | 0 | 126 |
| `texfat.ko` | 79 | 0 | 145 |
| `br_netfilter.ko` | 10 | 0 | **26** |

**每一個**原廠模組都不合，連 `br_netfilter` 這種小模組都是 —— 系統性差異，
代表 ASUS 出貨的 kernel 與他們釋出的 GPL 原始碼不完全一致
（我們的 `.config` 與 `/proc/config.gz` 已驗證過是零差異，
所以不是設定問題；也不只是我後來加的 `CONFIG_AIO=y` 造成的）。

> 這支工具第一版把 `readelf -x` 的輸出做了 4-byte 反轉，結果符號名稱全是亂碼、
> 380 個「全部找不到」。`readelf -x` 本來就是按檔案順序輸出位元組。

## 好消息：平台層已經全通

```
icnss 18800000.qcom,icnss: Platform driver probed successfully
icnss: QMI Server Connected: state: 0x981
icnss: WLAN FW is ready: 0xd87
```

這台是 **WCN3990 整合式（走 icnss）**，不是 PCIe 的 QCA6174
（`/sys/bus/platform/devices/18800000.qcom,icnss`，PCIe 匯流排上空的）。
icnss 平台驅動、QMI、韌體交握全部成功，`/vendor/firmware/wlan/qca_cld/`
的 `WCNSS_qcom_cfg.ini` 與 `bdwlan*.bin` 也都在。

**唯一缺的就是 qcacld-3.0 這顆驅動** —— 它註冊到 icnss 之後才會生出 `wlan0`。
kernel 樹裡 `drivers/net/wireless/` 底下的 `cnss`、`cnss2`、`cnss_crypto`、
`cnss_genl`、`cnss_prealloc`、`cnss_utils` 都在，defconfig 也已經有
`CONFIG_ICNSS=y`、`CONFIG_CLD_LL_CORE=y`、`CONFIG_WCNSS_MEM_PRE_ALLOC=y`、
`CONFIG_CFG80211=y` —— 平台側的前置條件齊備，qcacld 是 ASUS 當初外掛編譯的，
所以不在 GPL 釋出的樹裡。

## 取得來源

`LineageOS/android_kernel_oneplus_msm8998` 的 `lineage-16.0` 分支，
`drivers/staging/` 底下三個目錄都有：`qcacld-3.0`、`qca-wifi-host-cmn`、`fw-api`。
同平台（msm8998）、同 LineageOS 版本，而且已經接好 msm-4.4 的 Kconfig/Makefile。
`tools/75_fetch_qcacld.sh` 用 sparse clone 只取那三個目錄。

## 把 qcacld-3.0 接進 kernel

來源：`LineageOS/android_kernel_oneplus_msm8998` 的 `lineage-16.0`，
`drivers/staging/` 底下的 `qcacld-3.0`（468 檔）、`qca-wifi-host-cmn`（198 檔）、
`fw-api`（40 檔）。三個必須放在同一層 —— qcacld 的 Kbuild 寫死相對路徑
`WLAN_COMMON_ROOT := ../qca-wifi-host-cmn`。

編成 **built-in（`CONFIG_QCA_CLD_WLAN=y`）而不是模組**：
繞過 `CONFIG_MODULE_SIG_FORCE=y`，而且 OnePlus 同平台也是這樣設。
啟動鏈變成：
```
開機 -> __initcall_hdd_module_init6
     -> __ATTR(boot_wlan, 0220, NULL, wlan_boot_cb) 建立 /sys/kernel/boot_wlan/boot_wlan
使用者開 Wi-Fi -> libwifi-hal 寫 1（BoardConfig 的 WIFI_DRIVER_STATE_CTRL_PARAM）
     -> wlan_boot_cb -> qcacld 向 icnss 註冊 -> 與韌體交握 -> wlan0
```

### 三個「新驅動配舊平台」的編譯錯誤

qcacld 是 2019 年的版本，ASUS 的平台程式碼停在 2017 —— 跟使用者空間那些
「Oreo blob 配 Pie 函式庫」是同一類問題，只是搬到 kernel 層。

| # | 錯誤 | 修法 | 為什麼這樣選 |
|---|---|---|---|
| 1 | `cnss_utils_get_wlan_derived_mac_address` 未宣告 | 從 OnePlus 同步 `include/net/cnss_utils.h` + `cnss_utils.c` | cnss_utils 是無狀態的工具函式庫，整支換風險低 |
| 2 | `WLAN_FWR_SSR_BEFORE_SHUTDOWN` 未定義 | 把 `hdd_ipa_fw_rejuvenate_send_msg()` 改成 no-op | 不動 UAPI 的 `enum ipa_wlan_event` —— 後面的 `ipa_wan_event` 是接著 `IPA_WLAN_EVENT_MAX` 編號的，加值會位移所有 WAN/ECM 事件，可能破壞沿用的 ASUS IPA blob ABI。而收這則通知的 `ipacm` 我們根本沒裝 |
| 3 | `icnss_ce_request_irq` 參數不符（差一個 `struct device *dev`）+ 缺 3 個函式 | 在 qcacld 的 `pld_snoc.h` 加轉接層（11 個同名巨集 + 3 個 stub） | icnss 是**目前正常運作**的驅動（`WLAN FW is ready: 0xd87`），不動它；pld 本來就是吸收平台差異的層。照抄 OnePlus 的 `icnss.c` 會拉進 `linux/project_info.h`——他們自己的東西 |

> 第 2 點值得記：`enum ipa_wlan_event` 看起來只是個列舉，但它是 UAPI，
> 而且後續的 enum 接著它的 MAX 繼續編號 —— 在中間插值會靜默地改掉
> 一串跨 kernel/userspace 邊界的數值。

結果：`Image.gz-dtb` 從 13.9 MB 長到 15.9 MB，`boot.img` 17 MB（分割區 32 MB）。

## Wi-Fi 打通（2026-09-23 03:28）

`wlan0` + `p2p0` 出現，MAC `00:0a:f5:f1:6a:4e`（`00:0A:F5` 是 ASUSTek 的 OUI，
表示驅動有讀到裝置的 MAC 配置），wpa_supplicant 正常掃描 2.4G 與 5G，
設定畫面列出周邊 AP。

驅動層打通之後還卡了兩關，兩關都是「Android 9 的框架 × ASUS 的 Oreo vendor」：

### 1. `/sys/kernel/boot_wlan/boot_wlan` 權限

qcacld 編成 built-in，所以 HAL 不能用 insmod 啟動它，改成寫這個 sysfs 節點
（`BoardConfig` 的 `WIFI_DRIVER_STATE_CTRL_PARAM`）。節點由驅動的 initcall 建立：
```c
__ATTR(boot_wlan, 0220, NULL, wlan_boot_cb)
```
預設 `root:root 0220`，而 wifi HAL 跑在 `user wifi`：
```
android.hardware.wifi@1.0-service: Failed to access driver state control param Permission denied
android.hardware.wifi@1.0-service: Failed to load WiFi driver
```
在 `init.z01g.rc` 的 `on post-fs` 補 `chown wifi wifi` 即可。

### 2. wpa_supplicant 的設定檔

ASUS 的 `init.qcom.rc` 是 **Oreo 形式**的服務定義：
```
service wpa_supplicant /vendor/bin/hw/wpa_supplicant \
    -ip2p0 -Dnl80211 -c/data/misc/wifi/p2p_supplicant.conf \
    -iwlan0 -Dnl80211 -c/data/misc/wifi/wpa_supplicant.conf ...
```
在 Oreo，那兩份是由框架從範本複製到 `/data/misc/wifi` 的；
**Android 9 改用 HIDL 設定 supplicant，不再做這個複製**，於是檔案永遠不存在：
```
wpa_supplicant: Failed to open config file '/data/misc/wifi/p2p_supplicant.conf'
SupplicantStaIfaceHal: Failed to get ISupplicant
WifiNative: Failed to connect to supplicant
```
而且原廠 `/vendor/etc/wifi/` 只有 `wpa_supplicant.conf` 與兩個 overlay，
連 `p2p_supplicant.conf` 的範本都沒有（Oreo 是框架生成的）。

修法：自己寫一份 `p2p_supplicant.conf` 放進 device tree，
並在 `init.z01g.rc` 的 `on post-fs-data` 把兩份複製到 `/data/misc/wifi/`。
每次開機覆寫是安全的 —— Android 9 的已儲存網路存在 `WifiConfigStore.xml`，
不在 `wpa_supplicant.conf` 裡。

> 備案（沒用到）：改用 AOSP 自己編的 supplicant。
> `external/wpa_supplicant_8` 與 `hardware/qcom/wlan/qcwcn/wpa_supplicant_8_lib`
> 都在樹裡，`BOARD_WLAN_DEVICE := qcwcn` 也設好了；
> 麻煩的是 ASUS 的 `init.qcom.rc` 裡那個重複的服務定義會先被解析到，
> 要把整份 `init.qcom.rc` 搬進 device tree 才能改。

## Home 鍵：目前無解（已知原因）

指紋辨識器就是 Home 鍵，而 ASUS 的 `gxFpDaemon` 必須仲裁
「這次觸碰是要辨識指紋，還是要按 Home」。註冊指紋後 daemon 停在 IMAGE 模式：
```
[sig_in_image] --------HOME KEY DOWN In IMAGE Mode, clear it in TA--------
[sig_in_image] --------HOME KEY UP----------
[device_send_key] key = 102, value = 0, g_send_key_flag = 0, send_key_flag = 1
[device_send_key] Have already send UP.
```
DOWN 被 TA 吃掉，於是 UP 也送不出去。

把螢幕鎖改成「無」之後仍然沒反應（使用者實測，且沒有觸覺回饋），
所以不只是「驗證佔用」這麼單純 —— daemon 的模式切換還牽涉 ASUS 自己的
指紋設定 app（原廠有「按 Home 鍵回主畫面」開關）與框架整合，那套我們沒有，
而 daemon 是閉源的。

務實做法：開 LineageOS 內建的螢幕虛擬導覽列
（設定 → 系統 → 按鈕 → 導覽列），實體的返回／多工鍵不受影響。
