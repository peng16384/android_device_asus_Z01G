#!/usr/bin/env python3
"""
22.2：為發布的 zip 產生 LineageOS Updater 讀的 OTA JSON

  python3 tools/148_gen_ota_json.py <zip> <release tag> [輸出檔]

  例：python3 tools/148_gen_ota_json.py lineage-22.2-20260927-UNOFFICIAL-Z01G.zip 22.2-v1.0 ota/Z01G.json

手機端：device.mk 的 lineage.updater.uri =
  https://raw.githubusercontent.com/peng16384/android_device_asus_Z01G/main/ota/Z01G.json
這支產生的檔案就是要放到公開 repo main 分支的 ota/Z01G.json；zip 本身放在同名 tag 的 GitHub Release。

Updater（packages/apps/Updater 的 UpdatesCheckReceiver / Utils.isCompatible）怎麼決定要不要提供：
  version   必須等於 ro.lineage.build.version（22.2）
  romtype   必須等於 ro.lineage.releasetype（UNOFFICIAL）
  datetime  必須大於手機的 ro.build.date.utc —— 所以取 zip metadata 的 post-timestamp（就是那個值）
  id        唯一即可，用 zip 的 sha256（使用者也能拿來對下載檔）
只留一筆：Updater 只會提供比現行版本新的那筆，舊的留著沒有用。

Evolution X（檔名 EvolutionX-*）：格式不同，放 ota/evox/Z01G.json
（device tree 的 rro_overlays/EvolutionUpdaterOverlay 把 Updater 的網址指到那裡）。
  packages/apps/Updater 的 Utils.parseJson 一律 getString / getLong（缺欄位就整筆丟例外）：
  timestamp filename md5 size download version maintainer forum firmware paypal —— 後四個只是顯示，可以是空字串
  md5 被拿來當下載 ID；是否提供更新只比 timestamp 與手機的 ro.build.date.utc（同 LineageOS）
  例：python3 tools/148_gen_ota_json.py EvolutionX-15.0-20260928-Z01G-10.21-Unofficial.zip evox-10.21-v1.0 ota/evox/Z01G.json
"""
import hashlib
import json
import os
import re
import sys
import zipfile

OWNER_REPO = "peng16384/android_device_asus_Z01G"


def evox_entry(zpath, name, tag, meta, md5, sha256):
    m = re.match(r"EvolutionX-[\d.]+-\d{8}-Z01G-([\d.]+)-(\w+)\.zip$", name)
    if not m:
        sys.exit("!!! 檔名不像 EvolutionX-<Android>-<日期>-Z01G-<版本>-<類型>.zip：%s" % name)
    return {
        "maintainer": "peng16384",
        "currently_maintained": True,
        "oem": "ASUS",
        "device": "ZenFone 4 Pro (ZS551KL)",
        "filename": name,
        "download": "https://github.com/%s/releases/download/%s/%s" % (OWNER_REPO, tag, name),
        "timestamp": int(meta["post-timestamp"]),
        "md5": md5,
        "sha256": sha256,
        "size": os.path.getsize(zpath),
        "version": m.group(1),
        "buildtype": "userdebug",
        "forum": "https://github.com/%s" % OWNER_REPO,
        "firmware": "",
        "paypal": "",
        "github": "peng16384",
        "initial_installation_images": ["recovery"],
        "extra_images": [],
    }


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    zpath, tag = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) == 4 else None
    name = os.path.basename(zpath)

    with zipfile.ZipFile(zpath) as z:
        meta = dict(line.split("=", 1)
                    for line in z.read("META-INF/com/android/metadata").decode().splitlines()
                    if "=" in line)
    for k in ("post-timestamp", "pre-device", "ota-type"):
        if k not in meta:
            sys.exit("!!! metadata 缺 %s" % k)
    if "Z01G" not in meta["pre-device"].split(","):   # TARGET_OTA_ASSERT_DEVICE 的清單
        sys.exit("!!! pre-device=%s，不是 Z01G" % meta["pre-device"])
    h, h5 = hashlib.sha256(), hashlib.md5()
    with open(zpath, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
            h5.update(chunk)

    if name.startswith("EvolutionX-"):
        entry = evox_entry(zpath, name, tag, meta, h5.hexdigest(), h.hexdigest())
    elif name.startswith("lineage-22.2-") and "-UNOFFICIAL-" in name:
        entry = {
            "datetime": int(meta["post-timestamp"]),
            "filename": name,
            "id": h.hexdigest(),
            "romtype": "UNOFFICIAL",
            "size": os.path.getsize(zpath),
            "url": "https://github.com/%s/releases/download/%s/%s" % (OWNER_REPO, tag, name),
            "version": "22.2",
        }
    else:
        sys.exit("!!! 檔名不像 lineage-22.2-*-UNOFFICIAL-Z01G.zip 或 EvolutionX-*：%s" % name)
    text = json.dumps({"response": [entry]}, indent=2) + "\n"
    if out:
        os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        with open(out, "w", newline="\n") as f:
            f.write(text)
        print("寫入 %s" % out)
    sys.stdout.write(text)


if __name__ == "__main__":
    main()
