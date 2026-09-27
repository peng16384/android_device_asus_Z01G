# LineageOS for ASUS ZenFone 4 Pro (ZS551KL / Z01G / Z01GD)

Unofficial LineageOS ports for the ASUS ZenFone 4 Pro — a device that never
received anything newer than Android 8.0 from ASUS.

| | Android | Branch | Status |
|---|---|---|---|
| **LineageOS 22.2** | 15 | `lineage-22.2` | Daily use. Signed with this project's own keys, OTA updates |
| LineageOS 16.0 | 9 | `lineage-16.0` | Daily use (release `v1.0`) |

> 中文說明在下方 · [Chinese section below](#中文)

---

## Status

| | 22.2 | 16.0 |
|---|---|---|
| Boot / display / touch | ✅ | ✅ |
| Wi-Fi / Bluetooth | ✅ | ✅ |
| Audio, wired headset | ✅ | ✅ |
| Speakerphone in calls | ✅ | not tested |
| Camera: main, front, telephoto | ✅ | ✅ (telephoto only in apps that list every camera) |
| Fingerprint + Home key | ✅ | ✅ |
| Mobile data, **VoLTE calls** | ✅ | ✅ |
| GPS | ✅ | ✅ |
| Sensors | ✅ | ✅ |
| Auto-brightness | ✅ | ✗ not in `v1.0` |
| Vulkan | ✅ 1.1 | not tested |
| Widevine DRM | L3 only | not tested |
| NFC | ✗ not included | ✗ disabled |
| SELinux | **Enforcing** | **Enforcing** |
| Kernel | 4.4.302 + CIP 4.4 SLTS security fixes | 4.4.78 (ASUS stock source) |
| Signing / updates | own release keys, OTA via the Updater | test keys, manual |

Details: [docs/22.2/known-issues.md](docs/22.2/known-issues.md) ·
[docs/known-issues.md](docs/known-issues.md) (16.0).

## Branches

| Branch | Contents |
|---|---|
| `main` | This README, the docs, and the OTA update feed (`ota/`). No code. |
| `lineage-22.2` | The complete device tree + tooling for LineageOS 22.2 |
| `lineage-16.0` | The complete device tree + tooling for LineageOS 16.0 |

Version branches are self-contained and are never merged into each other.
Tags mark known-good points you can check out directly.

The device tree lives at the **root** of the version branch, so it can be
cloned straight into a LineageOS checkout:

```bash
git clone -b lineage-22.2 <this repo> device/asus/Z01G
```

The 22.2 kernel source is at
[peng16384/android_kernel_asus_msm8998](https://github.com/peng16384/android_kernel_asus_msm8998)
(branch `lineage-22.2-z01g`).

## Downloads, and what is proprietary

Ready-to-flash builds are attached to the tagged releases under **Releases**.
Read the flashing guide for your version first:
[22.2](docs/22.2/flashing.md) · [16.0](docs/flashing.md).

**The source repository contains no proprietary files** — not the
ASUS/Qualcomm vendor files and not the stock firmware. The tooling extracts
them from **your own device's stock image** (22.2: see the `lineage-22.2`
branch README; 16.0: [docs/building.md](docs/building.md)).

**The ROM zips in Releases do contain them**, as every unofficial ROM does:

- **22.2**: about 3,000 vendor files — ASUS's (camera, audio calibration,
  fingerprint, sensors, firmware) and the OnePlus 5's Qualcomm platform files
  as used by LineageOS, including its unmodified IMS stack.
- **16.0**: about 3,600 ASUS/Qualcomm vendor files and an `ims.apk` modified
  from ASUS's stock one (without it there are no calls, because VoLTE is the
  only voice path where 3G has been shut down).

Those files remain the property of their owners and are **not** covered by
this repository's license.

## Documentation

| | |
|---|---|
| [docs/22.2/flashing.md](docs/22.2/flashing.md) | 22.2: installing, LineageOS Recovery, updates |
| [docs/22.2/known-issues.md](docs/22.2/known-issues.md) | 22.2: known issues |
| [docs/flashing.md](docs/flashing.md) | Prerequisites, safety rules, recovery (**applies to both**) |
| [docs/building.md](docs/building.md) | 16.0: how to build it yourself |
| [docs/known-issues.md](docs/known-issues.md) | 16.0: known issues |

The version branches carry engineering write-ups in their `docs/`
(`bringup.md`, `kernel.md`, and for 16.0 `volte.md`) documenting how each
subsystem was brought up and, more usefully, the dead ends and wrong
conclusions along the way.

**On language:** this README is bilingual and `docs/volte.md` is written in
English, because that one is useful well beyond this device. The remaining
documents are in Traditional Chinese with an English summary at the top, so an
English reader can tell what is in them and decide whether to translate. Full
bilingual duplication was deliberately avoided — two copies drift, and a
drifted translation is worse than none.

## Credits

- [LineageOS](https://github.com/LineageOS) — the base
- 22.2: `LineageOS/android_device_oneplus_msm8998-common` and
  `android_device_oneplus_dumpling` (the device tree skeleton),
  `TheMuppets/proprietary_vendor_oneplus_msm8998-common` (platform blobs),
  `LineageOS/android_kernel_qcom_msm8998` (kernel base), and the
  [CIP project](https://www.cip-project.org/)'s 4.4 SLTS kernel (security fixes)
- 16.0: `LineageOS/android_device_xiaomi_msm8998-common` and
  `android_device_oneplus_msm8998-common` — the msm8998 trees it was modelled on
- [shakalaca/android_device_asus_Z01G](https://github.com/shakalaca/android_device_asus_Z01G)
  — board configuration reference
- [TeamWin/android_device_asus_Z01G](https://github.com/TeamWin/android_device_asus_Z01G) — TWRP
- [anestisb/vdexExtractor](https://github.com/anestisb/vdexExtractor) and
  [JesusFreke/smali](https://github.com/JesusFreke/smali) — used by the 16.0 IMS tooling

## License

Apache License 2.0 — see [LICENSE](LICENSE). The kernel is GPL-2.0.

This applies to the files in this repository. It does **not** apply to the
proprietary vendor files included in the release ROM zips.

---

<a name="中文"></a>

# 中文

給 ASUS ZenFone 4 Pro（ZS551KL）的非官方 LineageOS 移植。
這台機器原廠只更新到 Android 8.0 就停了。

| | Android | 分支 | 狀態 |
|---|---|---|---|
| **LineageOS 22.2** | 15 | `lineage-22.2` | 日常可用。用本專案自己的私鑰簽名、可以 OTA 更新 |
| LineageOS 16.0 | 9 | `lineage-16.0` | 日常可用（release `v1.0`）|

兩版的功能對照見上方英文的 Status 表。22.2 另外多了 Vulkan、CIP 的 kernel 安全修補、
私鑰簽名與系統內更新；限制是 Widevine 只有 L3、沒有 NFC。

代號說明：ASUS 自己的型號是 **Z01GD**，但社群（TWRP、shakalaca）的 codename
是 **Z01G**，本專案沿用 Z01G 以便與既有的樹對齊。

## 分支

| 分支 | 內容 |
|---|---|
| `main` | 說明、文件、OTA 更新清單（`ota/`），不含程式碼 |
| `lineage-22.2` | LineageOS 22.2 的完整 device tree 與工具 |
| `lineage-16.0` | LineageOS 16.0 的完整 device tree 與工具 |

各版本分支自成一體，彼此不合併。要回到某個確定可用的狀態請用 tag，
tag 是不動的定點。

device tree 放在版本分支的**根目錄**，可以直接 clone 進 LineageOS 原始碼樹：

```bash
git clone -b lineage-22.2 <本 repo> device/asus/Z01G
```

22.2 的 kernel 原始碼在
[peng16384/android_kernel_asus_msm8998](https://github.com/peng16384/android_kernel_asus_msm8998)
（`lineage-22.2-z01g` 分支）。

## 下載，以及哪些是專有檔案

每個 tag 對應的 **Releases** 附有可以直接刷的版本。
刷之前請先看該版本的刷機說明：[22.2](docs/22.2/flashing.md) · [16.0](docs/flashing.md)。

**原始碼儲存庫不含任何專有檔案**：沒有 ASUS/Qualcomm 的 vendor 檔，也沒有原廠韌體。
工具是從**你自己手機的原廠映像**抽取這些東西（22.2 見 `lineage-22.2` 分支的 README；
16.0 見 [docs/building.md](docs/building.md)）。

**Releases 的 ROM zip 則含有這些檔案**，所有非官方 ROM 都是如此：

- **22.2**：約 3,000 個 vendor 檔——ASUS 的（相機、音訊校正、指紋、感測器、韌體），
  以及 LineageOS 用在 OnePlus 5 上的 Qualcomm 平台檔案（含未修改的 IMS）。
- **16.0**：約 3,600 個 ASUS/Qualcomm 的 vendor 檔，以及從 ASUS 原廠修改而來的 `ims.apk`
  （少了它就不能打電話，因為在 3G 已關台的地方，VoLTE 是唯一的通話路徑）。

這些檔案的權利屬於原所有者，**不**適用本儲存庫的授權條款。

## 文件

| | |
|---|---|
| [docs/22.2/flashing.md](docs/22.2/flashing.md) | 22.2：安裝、LineageOS Recovery、更新 |
| [docs/22.2/known-issues.md](docs/22.2/known-issues.md) | 22.2：已知問題 |
| [docs/flashing.md](docs/flashing.md) | 前提條件、安全規則、出事怎麼救（**兩版都適用**）|
| [docs/building.md](docs/building.md) | 16.0：怎麼自己編 |
| [docs/known-issues.md](docs/known-issues.md) | 16.0：已知問題 |

各版本分支的 `docs/` 另有工程紀錄（`bringup.md`、`kernel.md`，16.0 另有 `volte.md`），
記的不只是「怎麼做成的」，還有走過的彎路與下錯的判斷——那部分通常比結論更有用。

**關於語言：** 這份 README 雙語，`docs/volte.md` 寫英文（那份的價值遠超過這台機器），
其餘文件維持中文並在最上面附英文摘要。刻意不做完整雙語——兩份會走鐘，
而走鐘的翻譯比沒有翻譯更糟。
