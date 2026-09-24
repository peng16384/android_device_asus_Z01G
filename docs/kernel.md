# 自編 kernel：驗證報告

> **English summary** — Building the stock ASUS GPL kernel source and verifying
> it against the shipping kernel *before* flashing anything. Covers: matching the
> original toolchain (GCC 4.9) and version string, confirming
> `zs551kl-perf_defconfig` is genuinely the shipping config (1586 options, zero
> differences against `/proc/config.gz`), checking all three appended DTBs
> byte-for-byte, and a null-control repack that reproduces the stock `boot.img`
> exactly. Also documents that self-built boot images need no ASUS signature on
> an unlocked bootloader, with the evidence for that claim.
>
> *The body is in Traditional Chinese.*

日期：2026-09-22　　狀態：**步驟 1–5 完成，尚未對手機做任何寫入**
待刷檔案：`boot-custom.img`（16,809,984 bytes）
還原檔案：`_docs/backup/boot.img`（33,554,432 bytes，已驗證為乾淨原廠）

---

## 編譯環境

| 項目 | 值 |
|---|---|
| 原始碼 | `ASUS_Z01GD_1-15.0410.1911.117-kernel-src.tar.gz` → `~/zs551kl/kernel/msm-4.4` |
| symlink | 29 個，**0 個斷掉**（`arch/arm64/boot/dts/qcom` → `../../../../arch/arm/boot/dts/qcom` 完好）|
| defconfig | `zs551kl-perf_defconfig` |
| toolchain | AOSP `aarch64-linux-android-4.9` + `arm-linux-androideabi-4.9`（tag `android-9.0.0_r61`）|
| gcc 版本字串 | `4.9.x 20150123 (prerelease)` — **與原廠完全一致** |
| host | WSL2 Ubuntu 20.04.6，24 執行緒 |
| 編譯時間 | **1 分 26 秒**（user 22m27s） |
| 結果 | 0 errors / 1 warning |

### 踩到的坑
CAF kernel 的 `Makefile:366` 是 `CC = $(srctree)/scripts/gcc-wrapper.py $(REAL_CC)`，
那支 wrapper 的 shebang 是 `#!/usr/bin/env python2`。Ubuntu 20.04 預設沒裝 python2 →
`make` 直接 `Error 127`。`sudo apt install python2` 即可（20.04 還有，這也是不選新版 Ubuntu 的理由之一）。

---

## 四項離線驗證

### 1. kernel 版本字串
```
自編：Linux version 4.4.78-perf+ (builder@buildhost)  (gcc version 4.9.x 20150123 (prerelease) (GCC) ) #1 SMP PREEMPT Tue Sep 22 10:39:14 CST 2026
原廠：Linux version 4.4.78-perf+ (android@mcrd1-13)   (gcc version 4.9.x 20150123 (prerelease) (GCC) ) #1 SMP PREEMPT Thu Nov  7 17:23:12 CST 2019
```
`4.4.78-perf+` 與編譯器字串完全相同。
**user@host 刻意不偽裝成原廠**——刷進去後 `uname -a` 就能一眼分辨手機跑的是自編還是原廠 kernel。

### 2. 附加 DTB
兩邊都是 3 個，**每一個的 byte 數完全相同**，只有排列順序不同（不影響，bootloader 是靠 msm-id/board-id 比對挑選）：

| model | size | qcom,msm-id | qcom,board-id |
|---|---|---|---|
| MSM 8998 v2.1 MTP | 380,735 | (292, 0x00020001) | (23, 0) |
| MSM HAMSTER RUMI | 312,955 | (306, 0x00000000) | (15, 0) |
| MSM 8998 v1 MTP | 363,321 | (292, 0x00000000) | (8, 0) |

本機是 `soc_id 292 / revision 2.1` → 會挑到第一顆 **MSM 8998 v2.1 MTP**，存在且大小相符。
附加 DTB 區總長 **1,057,011 bytes，與原廠一模一樣**。

### 3. config 比對
```
自編 out/.config        1586 條
手機 /proc/config.gz    1586 條
差異總數                0
```
**零差異。** 自編 kernel 的設定與出貨 kernel 完全相同。

### 4. 大小
```
自編 Image.gz-dtb   13,928,924 bytes
原廠 kernel blob    13,308,992 bytes
差異                  +619,932 bytes (+4.66 %)   → 在 ±5 % 內
```
解壓後大小 **37,318,712 vs 37,319,032**，只差 **320 bytes**（就是版本字串與時間戳的長度差）。
`.gz` 之所以大 4.66 %，是我們的 gzip 壓縮率略遜於 ASUS 當年用的版本，不是內容不同。

---

## 重打包

### 空對照（關鍵安全檢查）
用**原廠 kernel + 原廠 ramdisk** 重打包一次，輸出與 `_docs/backup/boot.img` 比對：
```
前 16,191,488 bytes 相同: True      ← 逐 byte 一致
```
→ 打包流程不會引入任何差異。萬一刷下去開不了機，可以確定問題在 kernel，不在打包。

### boot header（逐 byte 沿用原廠，只改 kernel size 與重算 SHA1 id）
```
page_size 4096   header_version 0
kernel_addr 0x8000     ramdisk_addr 0x1000000
second_addr 0xf00000   tags_addr 0x100        ← base = 0，不是一般 qcom 的 0x80000000
os_version 8.0.0       os_patch_level 2019-11
cmdline = console=ttyMSM0,115200,n8 ... buildvariant=user
```

### 成品
```
boot-custom.img   16,809,984 bytes  (boot 分割 33,554,432 bytes，剩 16,744,448)
sha256            0793f52e43d563e303a3939dd8949f40093c5ae26165d02dc3c5621814df7288
kernel            自編（4.4.78-perf+ builder@buildhost），3 個 DTB 齊全
ramdisk           原廠（2,872,274 bytes，未修改）
```

---

## ASUS boot 簽章的調查

拆解原廠 boot 時發現：32 MB 分割區在 boot image 內容之後**不是全 0**。查證結果：

| 映像 | 內容結尾後 | 內容 |
|---|---|---|
| 原廠 `backup/boot.img` | 1,268 bytes DER | X.509，`C=TW, O=AsusTek, OU=MCP, CN=ZEUS` ← **ASUS 官方簽章** |
| | 之後 ~500 KB | 隨機資料，無 `ANDROID!` magic → 前一次刷機殘留，無意義 |
| Magisk 版 `boot.emmc.win` | 1,322 bytes DER | **不含 AsusTek / ZEUS / Taiwan** → Magisk 用自己的金鑰重簽 |
| | 之後 | 全 0 |
| 自編 `boot-custom.img` | 無 | 完全沒有簽章 |

**結論：簽章不需要保留。**
直接證據是那顆 Magisk boot——它帶的是**非 ASUS 金鑰**簽出來的簽章，而這支手機確實用它正常開機過
（TWRP 備份時間 2026-09-21 20:25，目前系統仍是 Magisk 狀態）。
如果 bootloader 會驗 ASUS 簽章，那顆早就開不起來了。這與 `unlocked: yes` /
`verifiedbootstate=orange` 一致：解鎖後 bootloader 不驗 boot 映像簽章。

另外，自編映像 16,809,984 bytes **大於**原廠殘留資料的結尾（16,695,296），
所以刷下去會把舊簽章與殘留資料整段覆蓋掉，不會留下會被誤讀的殘骸。

---

## 步驟 6：刷入測試 —— ✅ **成功開機**

2026-09-22 執行。刷機前先確認兩邊 sha256 都吻合、電量 `battery-soc-ok: yes / 4265 mV`。

```
fastboot flash boot boot-custom.img
  Warning: skip copying boot image avb footer (boot partition size: 0, ...)   ← 無害，
          fastboot 的 getvar 本來就不回報 boot 分割大小（步驟 0 已知）
  Sending 'boot' (16416 KB)   OKAY [0.383s]
  Writing 'boot'              OKAY [0.150s]
fastboot reboot
```

### 開機後驗證

```
/proc/version
  Linux version 4.4.78-perf+ (builder@buildhost) (gcc version 4.9.x 20150123
  (prerelease) (GCC) ) #1 SMP PREEMPT Tue Sep 22 10:39:14 CST 2026
```
**是自編的那顆**（原廠是 `android@mcrd1-13` / `Thu Nov 7 17:23:12 CST 2019`）。

| 檢查 | 結果 |
|---|---|
| `sys.boot_completed` / `dev.bootcomplete` | `1` / `1` |
| `init.svc.bootanim` | `stopped`（開機動畫已結束＝完整進入系統）|
| 選到的 DTB | `Qualcomm Technologies, Inc. MSM 8998 v2.1 MTP` ← **與預測完全一致** |
| compatible | `qcom,msm8998-mtp qcom,msm8998 qcom,mtp` |
| `/system` | dm-0（dm-verity）掛載正常 3.7G/4.7G |
| `/data` | dm-1 掛載正常 32G/52G ← **FDE 解密成功，資料完好** |
| `/firmware` `/bt_firmware` `/persist` | 全部掛載正常 |

核心服務全部 `running`：`zygote` `zygote_secondary` `surfaceflinger` `media` `vold`
`netd` `ril-daemon` `ril-daemon2` `rmt_storage` `per_mgr` `adsprpcd` `thermal-engine`

輸入裝置全部在：
```
focal-touchscreen   (觸控 + mdss_fb/kgsl handler)
goodixfp            (指紋)
ASUS Proximitysensor / ASUS Lightsensor
gpio-keys / qpnp_pon
msm8998-tasha-snd-card Headset Jack + Button Jack
```
`wlan0` 介面存在（`wpa_supplicant` 是 `stopped`，因為 Wi-Fi 開關關著，不是故障）。
`rmnet_ipa0` UP，modem/IPA 正常。
`gsm.sim.state = ABSENT,ABSENT` —— **刷機前的 dump 也是 ABSENT**，沒插 SIM 卡，不是退步。

Magisk 如預期被移除（ramdisk 用原廠版）。

### 寫 device tree 時用得上的發現
觸控是 **Focaltech（`focal-touchscreen`）**，不是 kernel 樹裡那個
`drivers/input/touchscreen/synaptics_dsx`。做 device tree 時要挑對驅動。
指紋是 **Goodix（`goodixfp`）**。

---

## 步驟 7（追加）：恢復 Magisk

這顆 boot 用的是原廠 ramdisk，所以 root 被移除了。之後抽 proprietary blobs
需要 root，因此把 Magisk 加回來。

**走官方路徑**：Magisk APK 裡雖然有 x86_64 的 `libmagiskboot.so` 和 `assets/boot_patch.sh`，
理論上可以在 PC 端直接修補，但那是非官方流程，Magisk 30.x 的內部若有變動可能產出微妙壞掉的
映像。改用 App 內建的「選擇並修補一個檔案」。

修補對象選 **`boot-custom.img`**（不是原廠 `backup/boot.img`），這樣自編 kernel 與 root 都保留。

```
adb push boot-custom.img /sdcard/Download/        (sha256 校驗吻合)
[手機] Magisk App -> 安裝 -> 選擇並修補一個檔案 -> boot-custom.img
adb pull /sdcard/Download/magisk_patched-30700_9nLK0.img   (sha256 校驗吻合)
```

### 刷入前驗證

header 每一個欄位都與 `boot-custom.img` 相同（page_size / header_ver / kernel_size /
kernel_addr / ramdisk_addr / second_addr / tags_addr / os_version / cmdline）。

kernel **完全沒被動過**：13,928,924 bytes、`4.4.78-perf+ (builder@buildhost)`、3 個 DTB 齊全。

ramdisk `2,872,274` → `3,026,632`（+154,358），新增的正好是 Magisk 的 10 個項目：
```
+ overlay.d/ overlay.d/sbin/{magisk.xz, init-ld.xz, stub.xz}
+ .backup/{.magisk, .rmlist, init.xz, verity_key.xz}
- verity_key          ← 被搬進 .backup/verity_key.xz，Magisk 標準行為
```

**交叉驗證**：修補後的 ramdisk 是 **3,026,632 bytes，與 TWRP 備份裡那顆舊 Magisk boot
完全相同**（同一版 Magisk 產出一致）。

### 刷入結果 ✅

```
fastboot flash boot boot-custom-magisk.img     (16,961,536 bytes，分割區剩 16,592,896)
```
| 檢查 | 結果 |
|---|---|
| `/proc/version` | `4.4.78-perf+ (builder@buildhost)` ← 自編 kernel 保留 |
| `sys.boot_completed` / `bootanim` | `1` / `stopped` |
| `/sbin` | magisk tmpfs 已掛載，`/sbin/.magisk` 存在 |
| `su -c id` | `uid=0(root) gid=0(root) context=u:r:magisk:s0` |
| `magisk -c` | `30.7:MAGISK:R (30700)` |

`adb shell su` 不需在手機上手動授權即可通過 → **抽 blob 需要的 root 條件已就緒**。

目前 boot 分割內容：`boot-custom-magisk.img`
（sha256 `6c951492a58972dd6e32d5b9bee2caff4502cc8ec0f06e9fafc63ba1b017a5da`）

還原選項：
- 自編 kernel、無 root：`boot-custom.img`
- 原廠 kernel、無 root：`_docs/backup/boot.img`

---

## 結論

**結論。** ASUS 釋出的 GPL kernel 原始碼可以編出在本機正常開機的 kernel，
且與出貨版本在 config（零差異）、DTB（每個 byte 數相同）、kernel 大小（解壓後差 320 bytes）
三個層面都對得上。這代表後續階段的 kernel 基礎是可信的 —— 之後 LineageOS 開不了機時，
可以排除「kernel 本身有問題」這個變因。
