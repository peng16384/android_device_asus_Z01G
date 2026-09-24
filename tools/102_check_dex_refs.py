#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
檢查一個 dex 參照到的每一個類別，在裝置的 classpath 上是不是真的找得到。

  python3 tools/102_check_dex_refs.py <目標.dex 或 .apk> <jar 或 apk> ...

## 為什麼需要這支

改 ASUS 那顆 ims.apk 時，我一開始是「看到哪個類別對不上就查哪個」——
用手寫的對應表去比對 AIDL 簽章，等於把答案先假設進去。
結果漏掉了一整類：Pie 把 com.android.ims.ImsReasonInfo 這些**資料類別**
搬到了 android.telephony.ims.，但 ImsException / ImsConfigListener /
ImsManager 與整個 com.android.ims.internal.* 留在原地 —— 不是整包改名。
刷進去才看到：

    java.lang.NoClassDefFoundError: Failed resolution of:
        Lcom/android/ims/ImsReasonInfo;
    Process: com.android.phone   （ims.apk 跑在 phone 行程裡）

**逐一查看比對，不如對著實際編出來的 framework 全面掃一次。**

## 怎麼用

BOOTCLASSPATH 從裝置上 `adb shell echo $BOOTCLASSPATH` 拿，再加上這個 app
自己的 classpath（uses-library 的 jar 與 apk 本身）。out/ 底下對應的檔案是：

  out/target/product/Z01G/system/framework/{framework,telephony-common,
      voip-common,ims-common,ext,core-oj,core-libart,...}.jar

只比對「類別存不存在」，不看方法簽章 —— 方法層的錯是 AbstractMethodError /
NoSuchMethodError，那要另外驗。但類別層的錯最常見也最致命（整個行程起不來）。
"""
import os
import struct
import sys
import zipfile


def uleb(data, off):
    r = s = 0
    while True:
        b = data[off]
        off += 1
        r |= (b & 0x7F) << s
        if not b & 0x80:
            break
        s += 7
    return r, off


def dex_types(dex):
    """回傳 (全部參照到的型別, 這個 dex 自己定義的型別)。"""
    sid_size, sid_off = struct.unpack_from("<II", dex, 0x38)
    tid_size, tid_off = struct.unpack_from("<II", dex, 0x40)
    cd_size, cd_off = struct.unpack_from("<II", dex, 0x60)

    def gs(i):
        o = struct.unpack_from("<I", dex, sid_off + i * 4)[0]
        n, o = uleb(dex, o)
        return dex[o:o + n * 4].split(b"\x00")[0].decode("utf-8", "replace")

    types = [gs(struct.unpack_from("<I", dex, tid_off + i * 4)[0])
             for i in range(tid_size)]
    defined = {types[struct.unpack_from("<I", dex, cd_off + i * 32)[0]]
               for i in range(cd_size)}
    return types, defined


def dexes_of(path):
    """從 .dex / .jar / .apk 取出所有 classes*.dex 的位元組。"""
    if path.endswith(".dex"):
        return [open(path, "rb").read()]
    out = []
    with zipfile.ZipFile(path) as z:
        for n in sorted(z.namelist()):
            if n.startswith("classes") and n.endswith(".dex"):
                out.append(z.read(n))
    return out


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    target, cp = sys.argv[1], sys.argv[2:]

    have = set()
    missing_cp = []
    for p in cp:
        if not os.path.exists(p):
            missing_cp.append(p)
            continue
        ds = dexes_of(p)
        if not ds:
            missing_cp.append(p + "（裡面沒有 classes.dex）")
            continue
        for d in ds:
            _, defined = dex_types(d)
            have |= defined
    if missing_cp:
        print("⚠ classpath 上這些讀不到：")
        for p in missing_cp:
            print("    " + p)
        print("")
    print("classpath 提供 %d 個類別" % len(have))

    refs = set()
    own = set()
    for d in dexes_of(target):
        types, defined = dex_types(d)
        refs |= set(types)
        own |= defined
    have |= own

    bad = []
    for t in sorted(refs):
        if not t.startswith("L"):        # 基本型別與陣列
            continue
        base = t
        while base.startswith("["):
            base = base[1:]
        if not base.startswith("L"):
            continue
        if base not in have:
            bad.append(base)

    print("目標參照 %d 個型別，自己定義 %d 個" % (len(refs), len(own)))
    if not bad:
        print("")
        print(">>> 每一個外部參照都找得到")
        return
    print("")
    print("!!! 找不到的 %d 個：" % len(bad))
    for b in sorted(set(bad)):
        print("    " + b[1:-1].replace("/", "."))
    sys.exit(1)


if __name__ == "__main__":
    main()
