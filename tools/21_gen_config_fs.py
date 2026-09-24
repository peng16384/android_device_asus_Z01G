#!/usr/bin/env python3
"""
產生 device/asus/Z01G/config.fs

config.fs 定義 vendor 執行檔的 mode / user / group / Linux capabilities。
少了它，那些 daemon 會以錯誤的身分啟動或缺少 CAP_NET_BIND_SERVICE 之類的權限
——通常表現成「開得起來但 IMS/GPS/資料連線不動」，很難從症狀反推。

BoardConfig.mk 的 TARGET_FS_CONFIG_GEN 指向這個檔；檔案不存在的話，
`m nothing` 不會抱怨（它只讀 makefile），但真正做 image 時會
"No rule to make target"。所以在跑完整編譯前先補。

做法：以 xiaomi msm8998-common 的 config.fs 為底，
只保留「我們的 proprietary-files.txt 真的有收」的項目 ——
沒安裝的執行檔卻在 config.fs 裡宣告，會讓 fs_config 產生多餘條目。
"""
import os
import re
import sys

DEVICE_PATH = os.environ.get(
    'DEVICE_PATH',
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

REF = os.path.expanduser('~/zs551kl/reference/xiaomi_common/config.fs')
LIST = os.path.join(DEVICE_PATH, 'proprietary-files.txt')
DST = os.path.join(DEVICE_PATH, 'config.fs')


def load_shipped():
    """proprietary-files.txt 裡實際會安裝的路徑（以 /system 為根）。"""
    out = set()
    with open(LIST, encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            spec = line.lstrip('-').split('|', 1)[0]
            dest = spec.split(':', 1)[-1].strip()
            out.add(dest)
    return out


def parse_blocks(path):
    """把 config.fs 切成 [(標頭, [內容行])]。"""
    blocks, cur = [], None
    with open(path, encoding='utf-8') as fh:
        for raw in fh:
            line = raw.rstrip('\n')
            m = re.match(r'^\[(.+)\]\s*$', line)
            if m:
                cur = (m.group(1), [])
                blocks.append(cur)
            elif cur is not None and line.strip():
                cur[1].append(line)
    return blocks


def main():
    if not os.path.exists(REF):
        sys.exit(f'!!! 找不到參考 {REF}，先跑 tools/10_fetch_reference_trees.sh')
    shipped = load_shipped()
    blocks = parse_blocks(REF)

    kept, skipped = [], []
    for head, body in blocks:
        if head.startswith('AID_'):
            kept.append((head, body))          # AID 定義一律保留
        elif head in shipped:
            kept.append((head, body))
        else:
            skipped.append(head)

    with open(DST, 'w', encoding='utf-8') as fh:
        fh.write('# config.fs for ASUS ZenFone 4 Pro (ZS551KL / Z01G)\n')
        fh.write('#\n')
        fh.write('# 以 LineageOS xiaomi/msm8998-common 的 config.fs 為底，\n')
        fh.write('# 只保留 proprietary-files.txt 真的有收的執行檔。\n')
        fh.write('# 產生：tools/21_gen_config_fs.py\n')
        fh.write('#\n')
        fh.write('# 注意：本機是非 Treble，vendor 實際落在 /system/vendor，\n')
        fh.write('# 但 config.fs 的路徑仍寫 vendor/...（TARGET_COPY_OUT_VENDOR 會處理）。\n')
        fh.write('\n')
        for head, body in kept:
            fh.write(f'[{head}]\n')
            for line in body:
                fh.write(line + '\n')
            fh.write('\n')

    print(f'參考 {len(blocks)} 個區塊')
    print(f'  保留 {len(kept)} 個')
    for head, _ in kept:
        print(f'      {head}')
    print(f'  略過 {len(skipped)} 個（我們沒有收這些檔案）')
    for head in skipped:
        print(f'      {head}')
    print()
    print(f'輸出：{DST}')


if __name__ == '__main__':
    main()
