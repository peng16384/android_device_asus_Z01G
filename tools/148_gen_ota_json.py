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
"""
import hashlib
import json
import os
import sys
import zipfile

OWNER_REPO = "peng16384/android_device_asus_Z01G"


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
    if not name.startswith("lineage-22.2-") or "-UNOFFICIAL-" not in name:
        sys.exit("!!! 檔名不像 lineage-22.2-*-UNOFFICIAL-Z01G.zip：%s" % name)

    h = hashlib.sha256()
    with open(zpath, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)

    entry = {
        "datetime": int(meta["post-timestamp"]),
        "filename": name,
        "id": h.hexdigest(),
        "romtype": "UNOFFICIAL",
        "size": os.path.getsize(zpath),
        "url": "https://github.com/%s/releases/download/%s/%s" % (OWNER_REPO, tag, name),
        "version": "22.2",
    }
    text = json.dumps({"response": [entry]}, indent=2) + "\n"
    if out:
        os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        with open(out, "w", newline="\n") as f:
            f.write(text)
        print("寫入 %s" % out)
    sys.stdout.write(text)


if __name__ == "__main__":
    main()
