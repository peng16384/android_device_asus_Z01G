# device/asus/Z01G — LineageOS 22.2 for ASUS ZenFone 4 Pro (ZS551KL)

Device tree for LineageOS 22.2 (Android 15).
Clone this branch straight into a LineageOS 22.2 checkout:

```bash
git clone -b lineage-22.2 <this repo> device/asus/Z01G
```

The kernel lives in its own repository and goes to `kernel/asus/msm8998`:

```bash
git clone -b lineage-22.2-z01g https://github.com/peng16384/android_kernel_asus_msm8998 kernel/asus/msm8998
```
 Project overview, status, build and flashing guides are on
the **`main`** branch (`README.md` and `docs/`).

> **English summary** — Same approach as the `lineage-16.0` branch, rebuilt on
> the LineageOS 22.2 OnePlus 5 (msm8998) tree. The device is **not Treble**: the
> vendor files live inside `/system/vendor`, and the ASUS Oreo blobs link
> against system libraries directly, so a handful of AOSP projects need small
> patches (`patches/`). SoC-generic blobs come from the OnePlus 5 (LineageOS
> 22.2); everything tied to ASUS hardware or to firmware signed for this
> device's fuses comes from the stock ASUS 1911.117 image. No proprietary file
> is in this repository. SELinux is enforcing.
>
> *The body is in Traditional Chinese.*

---

## 這棵樹的形狀與取捨

**骨架是 LineageOS 22.2 的 OnePlus 5**（`android_device_oneplus_msm8998-common` +
`android_device_oneplus_dumpling`，版本與 commit 見 [`ORIGIN.md`](ORIGIN.md)），
併成單一 device tree，值換成 ZS551KL 的。和 16.0 一樣不拆 common ——
只有一支機器，拆開只是多一層間接。

**這台不是 Treble。** 沒有 vendor 分割，vendor 放在 system 裡：

```make
TARGET_COPY_OUT_VENDOR := system/vendor
# 不開 PRODUCT_FULL_TREBLE：ASUS 的 Oreo blob 直接連 system 的程式庫，
# ro.treble.enabled != true 時 linkerconfig 用 legacy 設定（單一預設 namespace）
```

**blob 分兩個來源**（規則與每一條排除的理由在 `tools/125_build_blob_lists_22.py` 開頭）：

| | 來源 | 清單 |
|---|---|---|
| SoC 共通（QTI 的 display / media / 網路 / IMS 堆疊…）| OnePlus 5，LineageOS 22.2 用的那一版（TheMuppets）| `proprietary-files-oneplus.txt` |
| ASUS 硬體專屬（相機、音訊校正、指紋、感測器、功放…）<br>與**經 PIL 載入的韌體** | ASUS 原廠 15.0410.1911.117 | `proprietary-files.txt` |

經 PIL 載入的韌體（ADSP 等）一律用 ASUS 的：這台的 OEM 熔絲已燒，
TZ 會拒絕別家簽的映像（`PAS_INIT_IMAGE` 回 `-60`）。

**`patches/` 是對 AOSP / LineageOS 專案的修改**，`tools/136_apply_patches_22.sh` 套用：

| | 為什麼 |
|---|---|
| `build/make` 0001 | A15 的 `fs_config_files_system` 會略過 `vendor/` 條目；vendor 在 system 裡時，config.fs 的 capabilities 就全部遺失 |
| `frameworks/native` 0001 | Oreo 的 blob 在 stack 上只替 `Parcel` 留 104 bytes，A15 的是 120 → 重排欄位縮回 104（指紋就是這樣壞的）|
| `hardware/interfaces` 0001 | 非 Treble 只有一個 linker namespace，audio HAL 服務與 libbinder_ndk 共用同一個 `ProcessState`；改走 `/dev/vndbinder` 會讓 thread pool 設定 abort，藍牙音訊的 AIDL 服務也會註冊到框架找不到的地方 |
| `hardware/interfaces` 0002 | sensors HAL 1.0 服務要 `input` 群組才讀得到 ASUS 的感測器節點 |

**kernel** 是 4.4.302（`LineageOS/android_kernel_qcom_msm8998` 的 lineage-20，
LineageOS 22.2 的 msm8998 機型用的就是它）+ ASUS 的驅動移植 +
CIP 4.4 SLTS 的安全修補（v4.4.302-cip114），見 [`docs/kernel.md`](docs/kernel.md)
與 [`docs/bringup.md`](docs/bringup.md) 第 15 節。

---

## 目錄

| | |
|---|---|
| `audio/` `configs/` | 音訊、媒體編解碼、效能等設定（ASUS 原廠的，必要處改過；`configs/media_profiles_V1_0.xml` 由 `tools/131` 產生）|
| `overlay*/` `rro_overlays/` | framework 資源覆蓋 |
| `rootdir/` | fstab、init rc、開機腳本 |
| `sepolicy/` | SELinux 政策（**enforcing**）|
| `patches/` | 對其他專案的修改（見上）|
| `tools/` | 建置、驗證、發布用的工具（`tools/12x`–`14x`；Evolution X 用的 `153`、`154`）|
| `docs/` | 工程紀錄（見下）|

## 編譯

這個 repo **不含任何專有檔案**。blob 從**你自己手機的原廠映像**抽出來
（dump 的方法見 `lineage-16.0` 分支的 `tools/06_dump_system.sh`）。大致流程：

```bash
bash device/asus/Z01G/tools/121_repo_sync_22.sh      # LineageOS 22.2 原始碼（~/lineage-22.2）
#   kernel/asus/msm8998          <- 上面那個 kernel repo 的 lineage-22.2-z01g 分支
#   ~/ref/proprietary_vendor_oneplus_msm8998-common  <- TheMuppets（lineage-22.2）
#   ~/ref/android_device_oneplus_msm8998-common       <- LineageOS（lineage-22.2）
bash device/asus/Z01G/tools/126_stage_sources_22.sh  # 原廠 system.img -> ~/asus/dump
bash device/asus/Z01G/tools/127_extract_22.sh        # 產生 vendor/asus/Z01G 與 vendor/asus/Z01G-oneplus
bash device/asus/Z01G/tools/136_apply_patches_22.sh  # 套 patches/
bash device/asus/Z01G/tools/133_build_22.sh          # breakfast Z01G + mka bacon
bash device/asus/Z01G/tools/135_verify_build_22.sh   # 檢查產物
```

> **`proprietary-files*.txt` 是產生出來的，手改會被蓋掉。**
> 要增減請改 `tools/125_build_blob_lists_22.py`
> （它要原廠映像的 inventory，`lineage-16.0` 分支的 `tools/08` 產生）。

**發布版**（私鑰簽名、產物裡不帶建置者資訊）另有一條路：
`tools/145`（產生金鑰）→ `tools/146`（加密備份）→ `tools/144`（編）→ `tools/147`（驗證簽名與個資）
→ `tools/148`（產生 OTA 用的 JSON）。

## Evolution X（vic，Android 15）

**同一棵 device tree、同一顆 kernel** 也能編 [Evolution X](https://github.com/Evolution-X/manifest)
的 `vic` 分支（它的基底就是 LineageOS 22.2）。差別只有：

| | LineageOS 22.2 | Evolution X vic |
|---|---|---|
| 原始碼 | `tools/121` | `tools/153`（`~/evox-vic`）|
| 放 kernel / blob / patch / 私鑰 | `tools/127`、`136` | `tools/154` 一次做完（4 個 patch 在 Evolution X 的 fork 上都能直接套；<br>另外套 `patches-evox/`：Evolution X 關掉了完整 OTA 的 brotli 壓縮，改回 AOSP 原本的寫法）|
| 編譯 | `breakfast Z01G` + `mka bacon` | `lunch lineage_Z01G-bp1a-userdebug` + `m evolution`（`ROM=evox tools/144`）|
| 私鑰目錄 | `vendor/lineage-priv/keys` | `vendor/evolution-priv/keys` |
| OTA 清單 | 屬性 `lineage.updater.uri` | 字串資源 `updater_server_url` —— `rro_overlays/EvolutionUpdaterOverlay` 蓋掉 |
| GApps | 無 | 內建 **mini** 版（`TARGET_USES_MINI_GAPPS`）：完整版的 zip 2.44 GiB，超過 GitHub Release 單檔 2 GiB；<br>mini + brotli 是 1.9 GiB。system 4.1 GB（分割 5 GB）|

`lineage_Z01G.mk` 裡的 `EVO_*` / `TARGET_SCREEN_*` 是給 Evolution X 的，LineageOS 不讀這些變數；
Updater 的 overlay 也只在 Evolution X 的樹裡才會裝。

## 工程紀錄

| | |
|---|---|
| [`bringup.md`](docs/bringup.md) | 22.2 的架構決定、blob 清單原則、開機除錯，以及之後每一個功能的根因與修法（喇叭、相機、GPS、Widevine、感測器、SELinux、Vulkan、CIP…）|
| [`kernel.md`](docs/kernel.md) | kernel 4.4.302：ASUS 的修改怎麼從 4.4.78 的原始碼移過來 |

記的不只是「怎麼做成的」，還有走過的彎路與下錯的判斷。
