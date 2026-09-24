# LineageOS 16.0 for ASUS ZenFone 4 Pro (ZS551KL / Z01G / Z01GD)

An unofficial LineageOS 16.0 (Android 9) port for the ASUS ZenFone 4 Pro
— a device that never received anything newer than Android 8.0 from ASUS.

**Everything works for daily use, including VoLTE calls.**
See [status](#status) below and [docs/known-issues.md](docs/known-issues.md).

> 中文說明在下方 · [Chinese section below](#中文)

---

## Status

| | |
|---|---|
| Boot / display / touch | ✅ |
| Wi-Fi / Bluetooth (A2DP + SCO) | ✅ |
| Audio, wired headset, volume | ✅ |
| Camera (main + front), video recording | ✅ |
| Fingerprint + Home key | ✅ |
| Mobile data | ✅ |
| **Voice calls (VoLTE)** | ✅ |
| GPS (GPS, GLONASS, BeiDou, Galileo, QZSS) | ✅ |
| SELinux | **Enforcing** |
| Telephoto camera | ✅ in apps that list every camera (e.g. Open Camera); the built-in Snap only switches main/front |
| NFC / Miracast / VR | Disabled during bring-up, not revisited |

The VoLTE work is the substantial part of this port and is likely the most
reusable piece for other devices — see
`docs/volte.md` on the `lineage-16.0` branch.

## Branches

| Branch | Contents |
|---|---|
| `main` | This README and the docs. No code. |
| `lineage-16.0` | The complete device tree + tooling for LineageOS 16.0 |

Version branches are self-contained and are never merged into each other.
Tags such as `v1.0` mark known-good points you can check out directly.

The device tree lives at the **root** of the version branch, so it can be
cloned straight into an AOSP checkout:

```bash
git clone -b lineage-16.0 <this repo> device/asus/Z01G
```

## Downloads, and what is proprietary

A ready-to-flash ROM zip is attached to each tagged release under
**Releases**. See [docs/flashing.md](docs/flashing.md) before using it.

**The source repository contains no proprietary files** — not the
ASUS/Qualcomm vendor files, not the stock firmware, and not the patched
`ims.apk`. The tooling extracts and rebuilds all of that from **your own
device's stock image** (see [docs/building.md](docs/building.md)).

**The ROM zip in Releases does contain them**, as every unofficial ROM does:
about 3,600 ASUS/Qualcomm vendor files, and an `ims.apk` modified from ASUS's
stock one (without it there are no calls, because VoLTE is the only voice path
where 3G has been shut down). Those files remain the property of their owners
and are **not** covered by this repository's license.

## Documentation

| | |
|---|---|
| [docs/building.md](docs/building.md) | How to build it yourself |
| [docs/flashing.md](docs/flashing.md) | Prerequisites, safety rules, recovery |
| [docs/known-issues.md](docs/known-issues.md) | Known issues and limitations |

On the `lineage-16.0` branch there are three engineering write-ups
(`docs/kernel.md`, `docs/bringup.md`, `docs/volte.md`) documenting how each
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
- `LineageOS/android_device_xiaomi_msm8998-common` and
  `android_device_oneplus_msm8998-common` — the msm8998 trees this one was
  modelled on
- [shakalaca/android_device_asus_Z01G](https://github.com/shakalaca/android_device_asus_Z01G)
  — board configuration reference
- [TeamWin/android_device_asus_Z01G](https://github.com/TeamWin/android_device_asus_Z01G) — TWRP
- [anestisb/vdexExtractor](https://github.com/anestisb/vdexExtractor) and
  [JesusFreke/smali](https://github.com/JesusFreke/smali) — used by the IMS tooling

## License

Apache License 2.0 — see [LICENSE](LICENSE).

This applies to the files in this repository. It does **not** apply to the
proprietary vendor files included in the release ROM zips.

---

<a name="中文"></a>

# 中文

給 ASUS ZenFone 4 Pro（ZS551KL）的非官方 LineageOS 16.0（Android 9）移植。
這台機器原廠只更新到 Android 8.0 就停了。

**日常功能都可用，包含 VoLTE 通話。**

代號說明：ASUS 自己的型號是 **Z01GD**，但社群（TWRP、shakalaca）的 codename
是 **Z01G**，本專案沿用 Z01G 以便與既有的樹對齊。

## 分支

| 分支 | 內容 |
|---|---|
| `main` | 說明與文件，不含程式碼 |
| `lineage-16.0` | LineageOS 16.0 的完整 device tree 與工具 |

各版本分支自成一體，彼此不合併。要回到某個確定可用的狀態請用 tag
（例如 `v1.0`），tag 是不動的定點。

device tree 放在版本分支的**根目錄**，可以直接 clone 進 AOSP 樹：

```bash
git clone -b lineage-16.0 <本 repo> device/asus/Z01G
```

## 下載，以及哪些是專有檔案

每個 tag 對應的 **Releases** 附有可以直接刷的 ROM zip。
刷之前請先看 [docs/flashing.md](docs/flashing.md)。

**原始碼儲存庫不含任何專有檔案**：沒有 ASUS/Qualcomm 的 vendor 檔、
沒有原廠韌體，也沒有改過的 `ims.apk`。工具鏈是從**你自己手機的原廠映像**
抽取並重建這些東西（見 [docs/building.md](docs/building.md)）。

**Releases 的 ROM zip 則含有這些檔案**，所有非官方 ROM 都是如此：
約 3,600 個 ASUS/Qualcomm 的 vendor 檔，以及從 ASUS 原廠修改而來的 `ims.apk`
（少了它就不能打電話，因為在 3G 已關台的地方，VoLTE 是唯一的通話路徑）。
這些檔案的權利屬於原所有者，**不**適用本儲存庫的授權條款。

## 文件

| | |
|---|---|
| [docs/building.md](docs/building.md) | 怎麼自己編 |
| [docs/flashing.md](docs/flashing.md) | 前提條件、安全規則、出事怎麼救 |
| [docs/known-issues.md](docs/known-issues.md) | 已知問題 |

`lineage-16.0` 分支另有三份工程紀錄（`docs/` 底下），記的不只是「怎麼做成的」，
還有走過的彎路與下錯的判斷——那部分通常比結論更有用。

**關於語言：** 這份 README 雙語，`docs/volte.md` 寫英文（那份的價值遠超過這台機器），
其餘文件維持中文並在最上面附英文摘要。刻意不做完整雙語——兩份會走鐘，
而走鐘的翻譯比沒有翻譯更糟。
