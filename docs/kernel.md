# kernel 4.4.302（為 LineageOS 22.2 做準備）

目標：把 ASUS 的驅動搬到 LineageOS 的 msm8998 kernel（`lineage-22.2`，4.4.302），
**先刷到現有的 16.0 上驗證**，再開始 22.2 的 bring-up。

為什麼先在 16.0 上驗：把 kernel 的問題與 Android 15 的問題拆開。
只寫 boot 分割，10 秒就能刷回原本的 boot。

---

## 為什麼是 22.2 而不是最新版

`git ls-remote` 查 LineageOS 的分支（2026-09-25）：

| repo | 最高版本 |
|---|---|
| `LineageOS/android`（主線）| `lineage-24.0` |
| `android_device_oneplus_msm8998-common` / `cheeseburger` / `dumpling` | `lineage-22.2` |
| `android_device_xiaomi_msm8998-common` / `sagit` | `lineage-22.2` |
| `android_kernel_oneplus_msm8998` / `android_kernel_xiaomi_msm8998` | `lineage-22.2`（4.4.302）|

msm8998 在 22.2 之後就沒有任何分支了。

22.2 的參考樹有兩件事與我們不同：
- **有獨立的 vendor 分割**（`TARGET_COPY_OUT_VENDOR := vendor`、`PRODUCT_FULL_TREBLE_OVERRIDE := true`）。
  這台沒有，規則是不改分割表。22.2 的 `build/make/core/board_config.mk` 仍接受
  `system/vendor`（甚至是預設值），但 Android 15 實際跑不跑得動沒有參考可對照。
- **IMS 是從 Fairphone 3 移植的 QTI IMS**（`proprietary-files.txt`：「Radio - IMS - from FP3 - 6.A.025.0」），
  16.0 的 `tools/99`（Oreo IMS 改到 Pie compat）到那裡用不上。

---

## ASUS 的基底：CAF `LA.UM.6.4.r1-05100-8x98.0`

ASUS 的 tarball 沒有 git 歷史。CAF 的 39 個 `LA.UM.6.4*8x98*` tag 的 `SUBLEVEL` 全是 78，
分不出來，所以改成逐一 `git diff --shortstat <tag> <ASUS>`
（`inventory/caf_tag_distance.txt`）。距離呈 V 字形，最低點：

```
LA.UM.6.4.r1-04900-8x98.0   744 檔
LA.UM.6.4.r1-05100-8x98.0   677 檔   <- 基底（05200 內容相同）
LA.UM.6.4.r1-05400-8x98.0   727 檔
```

CAF：`https://git.codelinaro.org/clo/la/kernel/msm-4.4.git`
WSL 內：`~/k22/caf`（remote `origin` = CAF，`asus` = `~/zs551kl/kernel/msm-4.4`）

---

## ASUS 改了什麼（相對於 CAF 基底，`inventory/asus_vs_caf.txt`）

| | 檔數 | |
|---|---|---|
| 新增 | 248 | 見下表（247 個共 +95,243 行）|
| 修改 | 262 | 90 個 diff 內有 ASUS 標記、172 個沒有（`inventory/modified_classified.txt`）|
| 刪除 | 167 | **全是 `.gitignore`**——ASUS 打包 tarball 時沒放，不是真的刪除 |

### 新增（`inventory/added_by_dir.txt`）

| 目錄 | 檔數 | 是什麼 |
|---|---|---|
| `drivers/sensors/ASH` | 77 | ASUS 感測器框架（近接、光線…）|
| `drivers/sensors/laser_focus` | 41 | 雷射對焦 |
| `drivers/media/platform` | 24 | 相機（camera_v2 的 ASUS 感光元件）|
| `drivers/exfat/{user,userdebug}` | 40 | ASUS 自帶的 exFAT |
| `arch/arm/boot`（dts）| 16 | `zs551kl-sr1-msm8998*` |
| `sound/soc/codecs` | 15 | TAS2557 功放等 |
| `drivers/input/touchscreen` | 14 | Focaltech 觸控 |
| `drivers/sensors/rgb_sensor` / `fingerprint` | 5 / 5 | RGB 感測器 / Goodix 指紋 |
| `drivers/dts_eagle` | 4 | DTS 音效 |

### 修改：有標記 vs 沒標記

有 ASUS 標記的 90 個集中在 fbdev（面板）、camera、充電（`power/supply`）、`soc/qcom`、
dts、codec、ufs、usb pd、thermal、mmc。

沒標記的 172 個**不能全當成安全修正**：除了 `fs/ext4`、`mm`、`kernel/locking` 這種
看起來是 upstream 修正的，也有 `sound/soc`、`drivers/usb`、`drivers/media`。
要逐一判斷：**22.2 的 kernel 已經有同樣修改的就跳過**（可以自動化）。
16.0 踩過的例子：`wcd9335.c` 的耳機孔 `g_DebugMode`（有標記，但同類的未必有）。

用 ASUS 標記找（`ASUS_BSP` / `ASUS BSP`）只抓得到 365 + 113 個檔案，而且混了雜訊
（x86 的 `asus_wmi`、各種驅動裡的 `ASUS_` 硬體 ID）——對 CAF 基底比才完整。

---

## 其他確認過的事

- 16.0 實際編譯用的 `~/lineage-16.0/kernel/asus/msm8998` 與 `~/zs551kl/kernel/msm-4.4`
  **工作目錄逐檔相同**。前者的 `.git` 只有 pristine 一個 commit（`tools/16` 的 `cp -al`
  當時複製的），看起來像「沒修改」，其實內容是最新的。以後以 `~/zs551kl` 為準。
- 參考 kernel：`~/k22/oneplus`（`LineageOS/android_kernel_oneplus_msm8998` lineage-22.2，淺層 clone）。
  qcacld-3.0 已經在它的 `drivers/staging/` 裡。

---

## 172 個沒標記的修改：分類完成（`inventory/unmarked_triage.md`）

逐行比對 22.2（`inventory/modified_vs_22.txt`），再人工看 diff：

| 分類 | 檔數 |
|---|---|
| 要搬或重做（跟硬體有關）| 18 |
| 驅動的建置設定（Makefile / Kconfig）| 11 |
| ASUS 除錯碼或自家功能，不搬 | 30 |
| 上游修正，22.2 已有或有改寫過的新版 | 112 |
| 雜訊（`.gitignore`）| 1 |

要搬的 18 個裡最值得注意的：SMB138x 充電晶片的 I²C 從 `i2c_7` 改到 `i2c_8`、
音訊路由 `PRI_MI2S` -> `SLIM0`、面板送出逾時 84 -> 168 ms（command mode 面板）、
螢幕關閉時讓觸控休眠的掛勾（在 `fbmem.c` 裡直接呼叫，新 kernel 應該改用 notifier）。

作為對照：有 ASUS 標記的 90 個，70 個判定為「22.2 沒有」——ASUS 自己的功能當然沒有，
說明這個比對方法是合理的。

## 新 kernel 的底：改用 qcom 的共用 kernel，不用 OnePlus 的

`~/k22/z01g`（分支 `z01g`），底是 **`LineageOS/android_kernel_qcom_msm8998` lineage-20**。

一開始用 OnePlus 的 lineage-22.2 kernel，DTS 三方合併的衝突裡看到 OnePlus 把
自己的硬體改動直接寫進 msm8998 的平台定義檔（「delete by xcb, gpio 21 are used by lcd」、
註解掉相機閃光燈 GPIO、引用 `OP-batterydata-3300mah.dtsi`）。拿它當合併基準，
**沒衝突的地方也會默默帶進 OnePlus 的設定**。

qcom 的共用 kernel：
- OnePlus 22.2 最新的 commit 就是「Merge qcom/lineage-20 into lineage-22.2」—— 22.2 的機型用的就是它
- 比較新：2026-08-14（最後一個 commit 是 `rtmutex` 的 backport）vs OnePlus 最後一次 merge 的 2025-05-04
- 跟 OnePlus 22.2 只差 209 項，幾乎都是 OnePlus 的東西；通用程式碼的差異是 qcom 比較新
- 沒有任何廠商的硬體改動；qcacld-3.0 也在

換底之後，相機感光元件、主機板定義、efuse 的衝突全部消失 —— 那些本來就是 OnePlus 造成的。

---

## DTS ✅（kernel repo 的 `f8755b83`）

量過變動量才決定用三方合併：24 個共用檔裡 16 個從 2018 到現在完全沒變，其餘最多差 62 行。

`tools/110_port_asus_dts.sh`（四個階段，可重跑）：
1. 三方合併：祖先 = CAF 基底、ours = qcom、theirs = ASUS。ASUS 的三種改法分開處理
   （分叉成 `zs551kl-sr1-*` 的 10 個、直接改共用檔的 6 個、全新的 5 個）
2. 解衝突：8 處，每處看過 diff3（含祖先）後決定，理由寫在工具裡
3. 標籤改名：qcom 把 `smb138x_parallel_slave` 改成 `smb1381_charger`（內容與 compatible 不變）
4. 把 `zs551kl-sr1-msm8998-v2.1-mtp.dtb` 加進建置清單

值得記的一處：**震動節點要整個照 ASUS**。qcom 把它換成新的 LED 類別驅動
（`qcom,qpnp-haptics`，屬性讀整數），ASUS 用舊驅動（`qcom,qpnp-haptic`，讀字串與位元組陣列）。
`compatible` 那一行不在衝突範圍內、已經自動變成 qcom 的，只照 ASUS 解衝突會得到
「新驅動 + 舊格式屬性」——驅動讀不懂也不報錯。這台實際在用舊驅動
（主機板檔設 `okay` 並加 `vibrator_en` GPIO；實機有 `/sys/class/timed_output/vibrator`）。

### 驗證：跟 ASUS 原版 DTB 逐屬性比

`tools/111_diff_dtb.py`：ASUS 的 DTB 在手機上跑過、確定可用，新版跟它的每一處差異都要解釋得通。

| | |
|---|---|
| 節點只在 ASUS 版 | 8：`smb138x-parallel-slave` 系列（改名了）、`ir_int`（只有 mediabox 參考板在用，qcom 刪了）、`dload_type@18`（qcom 修正成 `@1c`）|
| 節點只在新版 | 61：EAS 能耗表、coresight、pinctrl 新狀態、`msm-audio-apr`、proxy DAI 等 qcom 平台更新 |
| 屬性不同 | 63：I²C 多一個接腳狀態（×12）、EAS、BCL 熱插拔策略、LAB 省電門檻 20→70 等 qcom 更新 |
| `qcom,msm-id` / `qcom,board-id` | **相同**（bootloader 選 DTB 靠它們）|

比較工具本身踩過兩次：
1. 「值裡等於某個 phandle 的數字都換成節點路徑」—— dtc 的 phandle 從 1 開始編，
   `qcom,board-id <1 0>` 的 1 也被換掉，兩邊編號不同，造出 1964 處假差異
2. 用 `dtc -@` 的 `__local_fixups__` 找確切的 phandle 位置 —— dtc 1.5 只有編 overlay 才產生

最後改成逐 cell 比：數字相同，或兩邊各自是 phandle 且指向同一節點，就算相同。

---

### 後來的修正：直接改共用檔的 6 個改成分叉

第一次完整編譯 kernel 時，失敗在 **Qualcomm 參考板**的 DTB：
```
msm8998-cdp.dtsi:544.1-10 Label or path snd_934x not found
```
ASUS 在共用的 `msm8998-audio.dtsi` 刪掉了 tavil 音效卡，參考板還在引用。ASUS 原廠只編
自己那一個 DTB 所以沒事；`Image.gz-dtb` 會把清單上所有 msm8998 的 DTB 都編一遍。
改成跟其他 10 個一樣分叉成 `zs551kl-*`，由 `zs551kl-sr1-msm8998.dtsi` 改 include 分叉版，
共用檔維持 qcom 原樣。重新比對 DTB：差異與之前完全相同（8 / 61 / 63）——只換了組織方式。

`tools/110` 另外兩個修正：「qcom 那一邊」固定取 `origin/lineage-20`（不是 `HEAD`：
DTS 提交之後 `HEAD` 的共用檔已經帶著 ASUS 修改，會套兩次）；合併前先 `cd` 到暫存目錄
（從 Windows 端的 worktree 執行時，WSL 的 git 解析不了 `.git` 檔裡的 `G:/` 路徑）。

kernel repo：`f8755b83`（DTS）

---

## defconfig ✅（kernel repo 的 `54bd0e15`）

`tools/112_make_defconfig.sh` 產生 `arch/arm64/configs/z01g_defconfig`，**最後逐項檢查
每個要求的選項套用後真的生效**——Kconfig 遇到不存在或依賴不滿足的選項會靜靜丟掉。
（實例：qcom 自己的 `msmcortex-perf_defconfig` 還寫著 `NETFILTER_XT_MATCH_QTAGUID=y`，
但 qcom 已經把 xt_qtaguid 整個移除，這行從沒生效過。）

| 來源 | 內容 |
|---|---|
| 底 | qcom 的 `msmcortex-perf_defconfig`（ASUS 的 `zs551kl-perf_defconfig` 就是從 CAF 的這一份改的，差 133 行）|
| ASUS 相對 CAF（取 pristine commit，不是 `~/zs551kl` HEAD）| 新增 61、拿掉 13。拿掉的是 CoreSight 除錯與 `INPUT_HBTP_INPUT`；新增的一般選項中 `ASYNC`、`SYNC_TTY`、`ZRAM_LZ4_COMPRESS` 已不存在、`UID_CPUTIME` 改名 `UID_SYS_STATS`（qcom 已開）|
| 16.0 時我們加的 | `AIO`（adbd 要）、`QCA_CLD_WLAN`、`CNSS_UTILS` |
| LineageOS 22.2（OnePlus 5 defconfig）的通用選項 | BPF 全套（Android 12+ 的 netd 必須）、`OVERLAY_FS`、`SDFAT_FS`、`COMPAT_VDSO`、`CRYPTO_LZ4/SHA512`、**關掉 `MODULE_SIG_FORCE`**（16.0 時模組一個都載不起來的原因）|
| DTB | 只附加 `qcom/zs551kl-sr1-msm8998-v2.1-mtp` |

37 項全部生效。ASUS 驅動的 10 項（觸控 `TOUCHSCREEN_FT5X46`、TAS2557、PD 充電…）要等驅動搬進來。

**刻意沒動的**：排程維持 qcom 預設的 HMP（OnePlus 22.2 用 WALT + EAS；16.0 的效能 HAL 是照 HMP
寫的，現在換會跟 kernel 本身的問題混在一起）；`PSTORE` 需要 DT 裡的保留記憶體。兩者到 22.2 再處理。

⚠ **qtaguid 已經不存在**。Android 9 在 4.4 kernel 上的流量統計靠它，16.0 上測試時
要留意網路（netd 設 iptables 規則可能失敗）。

---

## 工具鏈 ✅

`tools/113_build_kernel.sh`，照 `vendor/lineage` 22.2 的 `config/BoardConfigKernel.mk`：

| | |
|---|---|
| clang | **clang-r536225（clang 19.0.1）**＝ `build/soong` 的 `ClangDefaultVersion`。AOSP prebuilts 的 `android15-qpr2-release` 分支（`main` 也還有），googlesource 的 `+archive` 單一目錄下載，1.1 GB（sha256 `1e77927f…`），解開 3.6 GB，放 `~/k22/toolchain/` |
| binutils | LLVM：`LLVM=1 LLVM_IAS=1`（條件是 clang 編譯 + LLVM binutils，兩者在 22.2 都是預設）|
| GCC 4.9 | 還是要給 `CROSS_COMPILE` / `CROSS_COMPILE_ARM32`（4.4 不能完全不用 GCC）|
| 建置者 | `KBUILD_BUILD_USER=android-build` / `KBUILD_BUILD_HOST=localhost` |

踩過：沒有 `LLVM_IAS=1` 時用 GCC 4.9 的舊 GNU as，看不懂 clang 19 預設的 DWARF 5
（`vgettimeofday.s:18: Error: file number less than one`）。

第一次完整編譯：`Image.gz-dtb` 13.7 MB，`Linux version 4.4.302-perf+ (android-build@localhost)`，
只附加 1 個 DTB（`MSM 8998 v2.1 MTP`）。**這個還沒有任何 ASUS 驅動，不刷。**

---

## 在 16.0 上實機測試（2026-09-25）✅ 開機、有畫面、觸控、震動

測試方法：新 kernel 包進 v1.0 zip 的 boot.img（`tools/115`，空對照逐 byte 相同），
只刷 boot 分割；還原用 `boot-16.0-rollback.img`（sha256 `ad375239…`）。

| 輪 | 症狀 | 根因 | 修法 |
|---|---|---|---|
| 1 | SurfaceFlinger 起不來 | GPU page fault（write）在 scratch buffer | 見下「GPU microcode」|
| 2 | 開機完成但沒畫面 | CP 卡住：`hw initialization failed to idle`，fence `retired:0` | 同上 |
| 3 | ✅ 有畫面、觸控正常；不震 | 震動馬達前的放大器 EN 腳（GPIO 60）沒人拉高 | 搬 ASUS 的 `qpnp-haptic.c` |
| 4 | ✅ 震動；約每 60 秒軟重啟 | 沒有 `xt_qtaguid` | 測試平台專用選項 |
| 4 | `time_daemon` 每 5 秒 SIGILL | EL0 讀不到 `CNTPCT_EL0` | `ARM_ARCH_TIMER_PCT_ACCESS` |
| 5 | Wi-Fi 打不開 | HAL 寫死 `/sys/kernel/boot_wlan/boot_wlan` | 測試平台專用選項 |

### GPU microcode：新 kernel 需要 patched 版的 `a530_pfp.fw`

新 kernel 帶了 CVE-2019-10567（Project Zero 2020 的 Adreno 漏洞）的修正：
scratch buffer 改成 privileged，每次 submit 後插 `CP_WHERE_AM_I` 回寫 rptr。
ASUS 的 `a530_pfp.fw` 是 **1.87 未修補版**（版本字 `0x005ff087`），兩件事都做不到：

- 第 1 輪：CP 用硬體的 RPTR_ADDR 回寫到 privileged buffer → page fault
- 第 2 輪（診斷：暫時拿掉 PRIVILEGED）：回寫成功，但不認得 `WHERE_AM_I` → CP 卡住。
  ⚠ 這一輪一度誤判成「GPU 好了」—— `GLES: Adreno 540` 是 userspace 報的，
  要看 fence 的 `retired` 有沒有前進

解法：**linux-firmware 的 `qcom/a530_pfp.fw` 1.87.01**（2020-09，Jordan Crouse，
版本字 `0x005ff08a`、patch 字 `0x00087001`；git blob `e991d4f9…` 與 repo 樹一致，
sha256 `7ab3cd91…`，授權 `LICENSE.qcom` 可再散布）。判準照上游 freedreno 的
`a5xx_ucode_check_version`：低 nibble 為 `0xa` 且 patch 字低 nibble ≥ 1 才有 `WHERE_AM_I`。
**`a530_pm4.fw` 不用換** —— ASUS 那份與 linux-firmware 的 git blob id 完全相同（`5b487d0e…`）。

⚠ 對照組：**OnePlus 22.2 的 kernel 沒有這個修正**（scratch 只有 `KGSL_MEMDESC_RANDOM`、
沒有 `WHERE_AM_I`），所以它用舊 microcode 能跑。我們不照抄，因為那等於把漏洞放回去。

測試時不動 `/system`：ueventd 的 `firmware_directories` 裡 `/odm/firmware/` 排在
`/vendor/firmware/` 前面，而 `/odm/firmware` 在 ramdisk 裡是指向不存在目錄的 symlink，
`tools/116_ramdisk_add.py` 把它換成真的目錄並放入新檔（其餘 64 個項目逐一驗證不變）。
**22.2 正式建置時要把它放進 vendor 的 firmware。**

### 震動：GPIO 60 放大器（kernel `b7944a97` + `effa0775`）

PMIC 有輸出、`timed_output` 介面齊全、HAL 也在跑，就是不震。ASUS 在 `qpnp-haptic.c`
的播放路徑先 `gpio_direction_output(60, 1)`、等 13 ms 再送波形，閒置後計時器拉低。
`tools/114` 三方合併，衝突 2 處：第 2 處是 sysfs 屬性表，兩邊都列了 `wf_s0…vmax_mv`，
串接會重複註冊 → 用 `port/haptics.attrs.c`（qcom 的表 + ASUS 新增的 7 個），
為此 `tools/114` 的解法表新增 `file:<檔名>`。GPIO 60 = TLMM（gpiochip0，base 0）。

### 16.0 測試平台專用的兩個選項（`z01g_t16_defconfig`，22.2 不開）

`tools/112` 現在產生兩份 defconfig；差異只有這三行：

```
CONFIG_NETFILTER_XT_MATCH_QTAGUID=y            （正式版：XT_MATCH_OWNER=y）
# CONFIG_NETFILTER_XT_MATCH_OWNER is not set
CONFIG_QCA_CLD_BOOT_WLAN_COMPAT=y
```

- **qtaguid**（kernel `a0c6c3df`，`tools/117_port_qtaguid.sh`）：Android 9 的 netd 用
  `-m owner --socket-exists` 掛在 raw PREROUTING / INPUT，上游 `xt_owner` 只允許
  OUTPUT / POSTROUTING → `iptables-restore: line 183 failed` → `Disabling bandwidth control`
  → NetworkPolicyManagerService 初始化提早 return（`mUsageStats` 沒設）→ 之後
  `isUidIdle()` NPE，system_server 約每 60 秒重啟（使用者看到的是亮度跳 100%、黑底鎖定畫面、
  「重新啟動後需要輸入 PIN 碼」）。出貨 kernel 與新 kernel 的 netfilter 設定逐條比對，
  只差這一條。Android 10 以後走 BPF，qcom 與 OnePlus 的新 kernel 都已刪掉 qtaguid。
- **boot_wlan**（kernel `215b60d5`）：16.0 的 BoardConfig
  `WIFI_DRIVER_STATE_CTRL_PARAM := "/sys/kernel/boot_wlan/boot_wlan"`（寫 1），
  新 qcacld 改用 `/dev/wlan` 寫 `ON` → HAL `Failed to load WiFi driver`。
  驅動本身正常（FW ready、`wlan0` 在）。相容節點寫 1 做的事與寫 ON 相同。
  **22.2 的 BoardConfig 直接改成 `/dev/wlan` / `ON` / `OFF`。**

### 正式版也要的：`ARM_ARCH_TIMER_PCT_ACCESS`（kernel `99c018d3`）

`time_daemon`（ASUS 的 Oreo blob，22.2 也是這支）`main+1576` 是 `mrs x8, CNTPCT_EL0`。
CAF 舊 kernel 開放 EL0 讀實體計數器，qcom 新 kernel 刻意關掉 → SIGILL（ILL_ILLOPC）。
新增選項（預設 n），`z01g_defconfig` 打開。虛擬計數器本來就開放，這個平台 CNTVOFF=0，
不多洩漏資訊。

### 指紋 ✅（kernel `f40cdd82` + `144e6fab`）

`drivers/sensors/fingerprint` 5 個新檔（`port/fingerprint.txt`，衝突 0），一次編過、0 警告。
`drivers/sensors` 的 Kconfig / Makefile 只手動加指紋那一條 —— ASUS 在同一檔還掛了
`rgb_sensor/`、`laser_focus/`、`ASH/`（`obj-y`），現在整份合併會因目錄不存在而編不過；
等搬感測器時再用 `tools/114` 整份合併。DT（`asus,fingerprint`）與依賴
（`g_update_bl`、wakelock、fb notifier）都已在。

實測：登錄、解鎖正常；Home 鍵經 `gxFpDaemon` 送 key 102（`goodixfp.kl` -> HOME）。
⚠ 開機後一開始按 Home 沒反應、過一陣子才可以 —— 原因**沒查到**：
那次用 `timeout` 砍 `getevent`（緩衝一起丟了，要用 `-c N`），又先 `logcat -c` 清掉了開機的 log。
下次開機後立刻按 Home、保留完整 log 再查。

藍牙：正常（使用者回報）。

### ⚠⚠ `git merge-file`（myers）會默默丟掉修改 —— 改用 `tools/merge3.sh`（2026-09-25）

搬充電時發現：ASUS 把 `qpnp-fg-gen3.c` 的 `fg_cleanup()` / `fg_gen3_probe()` 整段往後
搬了約 400 行、中間插入自己的函式。myers 對錯行，把 qcom 對這兩個函式的修改配到
ASUS 的新函式上 —— 合併結果的兩個函式是舊版，qcom 的 `alarm_try_to_cancel()`、
`prev_charge_status` 初始化**只剩在衝突區塊裡**；而衝突區塊外的其他 qcom 修改
**直接消失、不報衝突**。

| 演算法 | 衝突 | fg_cleanup 有 qcom 的修改 | probe 有 qcom 的修改 |
|---|---|---|---|
| myers（`git merge-file`，git 2.25 只有這個）| 7 | ✗ | ✗ |
| patience / histogram | 5 | ✓ | ✓ |

`tools/merge3.sh`：在暫存 repo 用 `git merge -X diff-algorithm=histogram`，輸出與退出碼
與 `merge-file -p --diff3` 相同；`tools/110`、`tools/114` 都改用它。

**已經進 kernel 的都重新驗證過**：開兩個停在 `d152ec62` 的 worktree，分別用舊（myers）
與新（histogram）工具重跑 DTS、顯示/觸控、core、震動、指紋 —— 53 個路徑**零差異**。
對照組（充電清單）確實比出 `qpnp-fg-gen3.c` 40 行差異，證明比對本身有效。

### 充電（kernel `c259b06e` + `ded4961c`）✅ 行為與原廠一致；大電流快充待測

實機（2026-09-25）：
- 電池參數：batt ID 98 kΩ -> `c11p1701_3400mah_apr18th2017_4p35v`（原廠同一組）
- FV：主晶片 4.357 V、並聯晶片 4.407 V（+50 mV）—— **與舊 kernel 的原廠驅動 log 完全相同**，
  是並聯充電的標準設計，電池端由主晶片限制
- 電腦 USB：SDP、ICL 475 mA、並聯關閉；USB PD 訊息只在開機前 7 秒出現 4 次（舊 kernel 32 次）
- 原廠充電器：DCP -> HVDCP2 -> **HVDCP3**、Type-C 3.0A、PD 協商成功；`asus_chg_flow_work`
  接手；JEITA 每 60 秒一次，全程 34 °C / GOOD / FV 4.358 V；ICL 2 A，接回電腦降回 475 mA
- ⚠ 插上時已 94～97%，全程 TAPER（約 250 mA），並聯只短暫啟用 —— **大電流快充沒驗到**，
  要在 50% 以下再測（看 FCC 分配、CHG_Mode FAST、溫度）
- 噪音：`usbpd: don't select pdo by userspace` 每 5 秒 —— ASUS 在 `select_pdo_store` 刻意擋掉
  userspace 選 PDO（由 ASUS 的 PD 策略自己選），是 hvdcp_opti 之類的在重試；
  `/asdf/gaugeMappingBackup` 讀不到 —— 重試 5 次後放棄（不掛 `/asdf` 的取捨，電量校正不跨開機）；
  `smb138x_parallel_get_prop: prop 4 not supported` 三次，未查

`port/charger.txt` 16 個檔（smb2 / smb138x / fg-gen3 / battery.c、apl6001、USB PD、
power_supply 屬性、of_batterydata），histogram 合併衝突 14 處，解法與理由在
`port/charger.resolve`。兩處要自己合成：
- fg-gen3 的重新充電條件（`port/charger.fg-recharge.c`）：qcom 的
  `|| !chip->charge_done` + ASUS 的 `bsoc` 與 `reporting_charge_full`
- smb-lib 的 HIGH_DUTY_CYCLE 中斷（`port/charger.hdc.c`）：ASUS 的「只排一次、600 ms」
  + qcom 的 IRQ 存在檢查

編譯修正：`f_dentry`；`rx_msg->len`（PDO 個數）-> `PD_MSG_HDR_COUNT(rx_msg->hdr)`
（新版的 `data_len` 單位是位元組，直接換會差 4 倍）；`ASUSEvtlog` / `ASUSErclog`
改寫到 kernel log（`kernel/asusdebug_z01g.c`，弱符號 —— 原版寫 `/asdf` 的檔案，這個 ROM 不掛）。

不在這一輪：`kernel/power/*`、`drivers/base/power/*`（休眠除錯）、thermal、msm-poweroff。

### 音訊 ✅（kernel `f4410649` + `178b554e` + `06da1750`）喇叭、有線耳機、通話都正常

`port/audio.txt`：TAS2557（14 個新檔）、wcd9335、wcd-mbhc-v2、msm8998 machine driver、
audio_calibration、q6adm topology、pcm routing、`drivers/base/regmap/internal.h`
（ASUS 在 `struct regmap` 加的 `proc_off_cache` / `proc_cache_lock`，wcd9335 的 /proc 傾印用）。

刻意不搬：q6asm / q6afe / q6lsm / msm-lsm-client / q6voice、`sound/core/timer.c`、`seq_*`、
`sound/usb/card.c`、`f_audio_source.c` —— CAF 2019 的安全修正，qcom 已有（逐一 grep 過）；
DTS Eagle —— 依賴的 CAF `msm-dts-eagle.c` 已被 qcom 移除，不影響出聲。

⚠ 清單檔名：`tas2557s/License text GPLv2.txt` 有空白，用 awk 取欄位會截斷（已從清單拿掉，不影響編譯）。

msm8998.c 的 TDM（衝突 1 處 + 兩處編譯修正，見 `port/audio.resolve` 與 kernel `06da1750`）：
ASUS 拿掉 TDM/MI2S pinctrl、TDM dai link 改用 CAF 的通用 `msm_tdm_be_ops`；qcom 反過來刪了
通用版、新增一批走 `msm8998_tdm_be_ops`（要 pinctrl）的 dai link。
-> 保留 qcom 的 TDM 函式、補回它要的 pinctrl 定義，ASUS 那條 dai link 改指 qcom 的 ops。
TDM 本機不用（三份 mixer_paths 沒有 TDM；TAS2557 在 PRI_MI2S，已確認 dai link 指向它）。

實機：TAS2557 `PG2.1 found`、`tas2557s_uCDSP.bin` 載入（119597 bytes，48 kHz 調校）、
`/proc/driver/audio_debug` = 0（音訊模式）。

| 訊息 | 判定 |
|---|---|
| `q6core_get_service_version: ... service id 7/8 with error -95`（播放時 29 次）| 7 = ASM、8 = ADM。新驅動查 ADSP 的 per-service API 版本，ASUS 的舊 ADSP 韌體不支援，退回預設版本 —— 實測出聲正常，無害 |
| `tasha_mbhc_get_result_params: Impedance detect ramp error`（插耳機 2 次）| 耳機阻抗量測；舊 kernel 的 log 沒錄到插耳機，無法對照。耳機播放與麥克風實測正常 |

### 感測器 ✅（kernel `1e566d88` + `db5bae45`）距離、自動亮度正常

`port/sensors.txt`（125 個檔，由 inventory 以 **tab** 切欄位產生）：ASH 框架、雷射對焦、
cm3323e，`drivers/sensors` 的 Kconfig / Makefile 整份合併。衝突 0，ASUS 驅動選項全部生效。

編譯時抓到 **ASUS 自己的 bug**：`Laser_log_cnt` 定義 `uint16_t`、兩處 `extern int` ——
讀會多讀相鄰 2 bytes、寫會把相鄰變數清掉。GNU ld 不查；ld.lld 的 LDST32 relocation
要求 4 bytes 對齊（位址 `...3FD2`）而擋下。另寫腳本比對 `drivers/`、`sound/` 所有
extern 與定義的型別，已搬的 ASUS 程式碼沒有別的（其餘命中都是不同驅動的同名變數）。

實機：cm3323e、雷射（Olivia）、cm36656（ID 0x0257，IRQ GPIO 120）都 probe 成功；
`ASUS Lightsensor` / `ASUS Proximitysensor` 進 sensorservice。距離感測器通話實測正常。
- 霍爾：沒有訊息 —— 這台本來就沒有（原廠的 input 裝置也只有距離與光線）
- 雷射讀不到 `/factory/laura_cal_data.txt`：**舊 kernel 也一樣**，16.0 從沒掛 `/factory`（ROM 的待辦）
- `module ID is not Olivia`：舊 log 沒錄到開機最前段，待搬相機時實際對焦再看

**自動亮度**不在 kernel：16.0 的 overlay 漏了 `config_automatic_brightness_available`
（AOSP 預設 false）。之後補上，值照抄原廠 framework-res.apk；
以 TWRP 覆寫 `/system/vendor/overlay/framework-res__auto_generated_rro.apk` 實測，出現且會跟著變。

### 相機 ✅（kernel `b0a1289a`）三顆鏡頭、對焦、閃光燈、雷射對焦都正常

`port/camera.txt`（37 個檔）：flash / actuator / eeprom / cci / dt_util / sensor_driver、
`ois-rumba`（取代 CAF 的 `ois/`）、`preisp_driver`、`fac_camera`、`cam_soc_api.c`
（`msm_camera_get_clk_info_internal` 去 static）、相機標頭檔。
不搬：camera_v2/ais 的 `msm_camera_io_util.c`、`jpeg_10`、`vidc` —— CAF 安全修正，qcom 已有。
衝突 1 處（`msm_actuator.c`）：qcom 的 `step_position_table == NULL` 檢查 + ASUS 簡化的移動條件
（`port/camera.actuator-move.c`）。一次編過、0 警告；vmlinux 有 63 個相關符號；
出貨 defconfig 的相機選項全在；extern 型別 0 處不一致。

實機：imx362 / imx319 / imx351 都 probe 成功並讀到 ASUS OTP；OIS（ID 0x730，15 個 proc）；
preisp 韌體 `preisp.rkl` 下載成功；雷射拍照時連續量測（例：Range 209 mm、ErrCode 0、Confidence 898）。

| 訊息 | 判定 |
|---|---|
| `proc_dir_entry 'driver/front_otp' already registered` + WARN | **舊 kernel 同樣有** —— ASUS 的 `create_proc_otp_thermal_file()` 每顆鏡頭都建同名 proc |
| 4 個 `Unbalanced enable for IRQ 765/766` WARN | **舊 kernel 同樣 4 個** —— `init.asus.audbg.sh` 切到音訊模式時 ASUS 重複 enable 耳機偵測中斷 |
| `msm_eeprom_platform_probe failed`、`No/Error Actuator GPIOs` | 搬相機之前就有（DT 裡沒用到的節點）|

### enforcing ✅（2026-09-25）全部功能在 enforcing 下實測正常

同一顆 kernel、cmdline 換成 `androidboot.selinux=enforcing`，ramdisk 仍是 v1.0 的
（只用 `tools/116 --replace` 換 sepolicy、加 GPU microcode）。
ueventd 讀 ramdisk 的 `/odm/firmware`：政策已允許 `ueventd rootfs:file read`，microcode 照常載入。

第一輪 5 類 denial：3 類是 16.0 就已知的（dpmd、qti_init_shell 的 lcd_density 與 alarm），
2 類是 **16.0 政策本身的缺口**、與 kernel 無關（之後補上）：
- 感測器 HAL 寫 `/sys/devices/virtual/sensors/*/switch` 被擋 —— 實體目錄是通用 sysfs
  （`/sys/class/sensors` 的 symlink 才是 `sysfs_sensors`）。v1.0 沒有自動亮度、框架從不開
  光線感測器，所以沒碰過；**enforcing 下自動亮度會失效**。genfs 標成 `sysfs_sensors`。
- 藍牙 HAL 搜尋 `/asusfw`：它先找 `/asusfw/Bluetooth/crbtfw21.tlv`（這台沒有）再退
  `/bt_firmware`。只給 `dir search`，讓它拿 ENOENT 而不是 EACCES。

第二輪（新政策，所有功能用過一輪，audit_lost=1）：已知 3 條 + `untrusted_app` 7 條
（App 打探 `/dev/block`、掛載點、`/proc/version`、電池 sysfs —— 本來就該擋）。
使用者實測：畫面、觸控、Wi-Fi、藍牙、指紋、Home、聲音、相機、通話、距離、自動亮度都正常。

### 還沒處理的

| 項目 | 狀態 |
|---|---|
| 錄影 | ✅ 正常（相機那一輪之後補測）|
| Home 鍵開機後一段時間沒反應 | 見上，待重現 |
| DTS Eagle | 見音訊一節 |
| 雷射校正檔（`/factory`）| ROM 側：唯讀掛 `/factory` |
| enforcing | ✅ 見上 |
| 大電流快充 | 電量 50% 以下再測 |
| 充電 | 高通標準的 smb2 / fg-gen3 在管（ASUS DT：JEITA 0/10/50/60 °C、截止 150 mA；實測 4.297 V、電腦 USB 500 mA）；ASUS 在 `drivers/power/supply/qcom` 改的約 10 個檔還沒搬 —— 在那之前不用快充頭、不整夜無人看管 |
| 喇叭 | ADSP ONLINE、音效卡在；TAS2557 功放驅動還沒搬 |
| `q6core_get_service_version ... error -95` | 新音訊驅動查詢較新的 AVS API，ASUS 的舊 ADSP 韌體不支援；搬功放時一起看 |
| `firewall set_uid_rule standby <uid> allow` 失敗（一次）| 舊 kernel 的 log 沒錄到那個時機，不確定是不是新的；要 root 跑 iptables 才能查 |
| 觸控韌體每次開機重刷 | ASUS 驅動原本就這樣（舊 kernel 也是），不是新問題 |

---

## 下一步

1. ~~172 個沒標記的修改~~ ✅　2. ~~kernel repo + DTS~~ ✅　3. ~~defconfig~~ ✅　4. ~~工具鏈~~ ✅
5. ~~開機必要的驅動：面板、觸控、USB/adb~~ ✅　6. ~~第一個里程碑：16.0 上開機、有畫面、adb~~ ✅
7. ~~指紋（Goodix）~~ ✅
8. ~~充電~~ ✅（大電流快充待補測）→ ~~音訊~~ ✅ → ~~感測器~~ ✅ → ~~相機~~ ✅
9. 收尾：~~enforcing 實測~~ ✅、~~錄影~~ ✅、快充補測；之後進入 LineageOS 22.2 userspace 的 bring-up
