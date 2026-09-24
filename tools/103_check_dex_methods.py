#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
檢查一個 dex 參照到的每一個**方法與欄位**，在 classpath 上是不是真的找得到。

  python3 tools/103_check_dex_methods.py <目標.dex 或 .apk> <jar 或 apk> ...

## 為什麼需要這支

tools/102 只比對類別存不存在。但還有一整類錯是類別在、方法不在：

    java.lang.NoSuchMethodError: No virtual method
        parseAndKeepRawInput(Ljava/lang/String;Ljava/lang/String;)...
        in class Lcom/android/i18n/phonenumbers/PhoneNumberUtil;
    at org.codeaurora.ims.CountryCodeTableAsus.formatNumberAsus

（libphonenumber 把第一個參數從 String 改成 CharSequence。）

欄位也一樣會錯，而且常跟類別搬家綁在一起：把 com.android.ims.ImsSsData
改指到 android.telephony.ims.ImsSsData 之後，CAF 版的欄位 mServiceType
在 Pie 叫 serviceType —— 會是 NoSuchFieldError。

這種錯只有執行到那一行才會爆，而每一輪「改 -> 編 -> 刷 -> 測」要 20 分鐘。
與其一次抓一個，不如對著實際編出來的 framework 全掃。

## 比對方式

對每一個外部方法參照 (類別, 名稱, 簽章)，沿著該類別在 classpath 上的
**父類別與介面**往上找同名同簽章的方法。找不到就回報。

不處理的（會漏報，不會誤報）：
  - 陣列型別上的方法（clone 等）—— 直接跳過
  - classpath 上完全沒有的類別 —— 那是 tools/102 的守備範圍
  - 反射呼叫
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


class Dex(object):
    def __init__(self, data):
        self.d = data
        self.sid_size, self.sid_off = struct.unpack_from("<II", data, 0x38)
        self.tid_size, self.tid_off = struct.unpack_from("<II", data, 0x40)
        self.pid_size, self.pid_off = struct.unpack_from("<II", data, 0x48)
        self.fid_size, self.fid_off = struct.unpack_from("<II", data, 0x50)
        self.mid_size, self.mid_off = struct.unpack_from("<II", data, 0x58)
        self.cd_size, self.cd_off = struct.unpack_from("<II", data, 0x60)
        self._str = {}

    def s(self, i):
        if i in self._str:
            return self._str[i]
        o = struct.unpack_from("<I", self.d, self.sid_off + i * 4)[0]
        n, o = uleb(self.d, o)
        v = self.d[o:o + n * 4].split(b"\x00")[0].decode("utf-8", "replace")
        self._str[i] = v
        return v

    def t(self, i):
        return self.s(struct.unpack_from("<I", self.d, self.tid_off + i * 4)[0])

    def type_list(self, off):
        if off == 0:
            return []
        n = struct.unpack_from("<I", self.d, off)[0]
        return [self.t(struct.unpack_from("<H", self.d, off + 4 + k * 2)[0])
                for k in range(n)]

    def proto(self, i):
        base = self.pid_off + i * 12
        ret = self.t(struct.unpack_from("<I", self.d, base + 4)[0])
        params = self.type_list(struct.unpack_from("<I", self.d, base + 8)[0])
        return "(" + "".join(params) + ")" + ret

    def method(self, i):
        base = self.mid_off + i * 8
        cls_idx, proto_idx = struct.unpack_from("<HH", self.d, base)
        name_idx = struct.unpack_from("<I", self.d, base + 4)[0]
        return self.t(cls_idx), self.s(name_idx), self.proto(proto_idx)

    def field(self, i):
        base = self.fid_off + i * 8
        cls_idx, type_idx = struct.unpack_from("<HH", self.d, base)
        name_idx = struct.unpack_from("<I", self.d, base + 4)[0]
        return self.t(cls_idx), self.s(name_idx), self.t(type_idx)

    def classes(self):
        """yield (類別, 父類別, [介面], set((名稱, 簽章)), set((欄位名, 型別)))"""
        for i in range(self.cd_size):
            base = self.cd_off + i * 32
            cls_idx, _, sup_idx, if_off = struct.unpack_from("<IIII", self.d, base)
            data_off = struct.unpack_from("<I", self.d, base + 24)[0]
            name = self.t(cls_idx)
            sup = self.t(sup_idx) if sup_idx != 0xFFFFFFFF else None
            ifs = self.type_list(if_off)
            methods = set()
            fields = set()
            if data_off:
                o = data_off
                sf, o = uleb(self.d, o)
                inf, o = uleb(self.d, o)
                dm, o = uleb(self.d, o)
                vm, o = uleb(self.d, o)
                for cnt in (sf, inf):
                    idx = 0
                    for _ in range(cnt):
                        diff, o = uleb(self.d, o)
                        idx += diff
                        _, o = uleb(self.d, o)      # access_flags
                        _, fn, ft = self.field(idx)
                        fields.add((fn, ft))
                for cnt in (dm, vm):
                    idx = 0
                    for _ in range(cnt):
                        diff, o = uleb(self.d, o)
                        idx += diff
                        _, o = uleb(self.d, o)      # access_flags
                        _, o = uleb(self.d, o)      # code_off
                        _, n, p = self.method(idx)
                        methods.add((n, p))
            yield name, sup, ifs, methods, fields


def dexes_of(path):
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

    # classpath：類別 -> (父類別, 介面, 方法集合)
    info = {}
    for p in cp:
        if not os.path.exists(p):
            print("⚠ 讀不到 %s" % p)
            continue
        for d in dexes_of(p):
            for name, sup, ifs, ms, fs in Dex(d).classes():
                if name in info:
                    info[name][2].update(ms)
                    info[name][3].update(fs)
                else:
                    info[name] = (sup, ifs, set(ms), set(fs))
    print("classpath 提供 %d 個類別" % len(info))

    own = {}
    refs = set()
    frefs = set()
    for d in dexes_of(target):
        dx = Dex(d)
        for name, sup, ifs, ms, fs in dx.classes():
            own[name] = (sup, ifs, set(ms), set(fs))
        for i in range(dx.mid_size):
            refs.add(dx.method(i))
        for i in range(dx.fid_size):
            frefs.add(dx.field(i))
    info.update(own)

    def has(cls, nm, pr, seen=None):
        """沿著父類別與介面找 (名稱, 簽章)。"""
        if seen is None:
            seen = set()
        if cls in seen or cls not in info:
            return False
        seen.add(cls)
        sup, ifs, ms, _fs = info[cls]
        if (nm, pr) in ms:
            return True
        if sup and has(sup, nm, pr, seen):
            return True
        return any(has(i, nm, pr, seen) for i in ifs)

    bad = []
    for cls, nm, pr in sorted(refs):
        if cls in own:                      # 自己定義的類別
            continue
        if not cls.startswith("L"):         # 陣列等
            continue
        if cls not in info:                 # 類別本身就不在 -> tools/102 的範圍
            continue
        if nm in ("<init>", "<clinit>"):
            # 建構式不走繼承，直接看該類別自己有沒有
            if (nm, pr) in info[cls][2]:
                continue
            bad.append((cls, nm, pr))
            continue
        if not has(cls, nm, pr):
            bad.append((cls, nm, pr))

    def hasf(cls, nm, ty, seen=None):
        if seen is None:
            seen = set()
        if cls in seen or cls not in info:
            return False
        seen.add(cls)
        sup, ifs, _ms, fs = info[cls]
        if (nm, ty) in fs:
            return True
        if sup and hasf(sup, nm, ty, seen):
            return True
        return any(hasf(i, nm, ty, seen) for i in ifs)

    fbad = []
    for cls, nm, ty in sorted(frefs):
        if cls in own or not cls.startswith("L") or cls not in info:
            continue
        if not hasf(cls, nm, ty):
            fbad.append((cls, nm, ty))

    print("目標參照 %d 個方法、%d 個欄位" % (len(refs), len(frefs)))
    if not bad and not fbad:
        print("")
        print(">>> 每一個外部方法與欄位都找得到")
        return
    if bad:
        print("")
        print("!!! 找不到的方法 %d 個：" % len(bad))
        for cls, nm, pr in bad:
            print("    %s.%s%s" % (cls[1:-1].replace("/", "."), nm, pr))
    if fbad:
        print("")
        print("!!! 找不到的欄位 %d 個：" % len(fbad))
        for cls, nm, ty in fbad:
            print("    %s.%s : %s" % (cls[1:-1].replace("/", "."), nm, ty))
    sys.exit(1)


if __name__ == "__main__":
    main()
