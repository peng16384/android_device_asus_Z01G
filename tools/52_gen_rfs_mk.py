#!/usr/bin/env python3
"""
從原廠映像產生 /vendor/rfs 的目錄與 symlink 建立規則。

為什麼需要：
    原廠 /system/vendor/rfs 是「純目錄 + symlink」的樹（25 個目錄、44 條 symlink，
    一個一般檔案都沒有）。tools/31_build_blob_list.py 會跳過 symlink
    （os.walk 會把指向檔案的 symlink 列進 files，之前造成 199 條抽不到的假條目），
    而空目錄本來就不會出現在檔案清單裡 —— 結果整棵 rfs 在我們的 image 裡不存在。

    後果（_docs/dbg5 的 logcat，tftp_server 佔了 16 萬行）：
        tftp-server : mkdir failed: [/vendor/rfs/msm/mpss/readwrite] [No such file or directory]
        tftp-server : mkdir failed: [/vendor/rfs] [Read-only file system]
    rfs 是 modem / adsp / slpi 用來讀寫 EFS 類檔案的路徑，RIL 會用到。

做法：
    產生 device/asus/Z01G/rootdir/rfs.mk，用 LOCAL_POST_INSTALL_CMD 在
    安裝 fstab.qcom 之後建目錄與 symlink。PRODUCT_COPY_FILES 做不到 symlink，
    把 symlink 寫進 blob 清單也抽不出來，所以只能用 Makefile 指令。

用法（WSL，需先掛好 /mnt/zs_system）：
    python3 tools/52_gen_rfs_mk.py
"""
import os

DEVICE_PATH = os.environ.get(
    'DEVICE_PATH',
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

SRC = '/mnt/zs_system/vendor/rfs'
DST = os.path.join(DEVICE_PATH, 'rootdir/rfs.mk')

dirs, links = [], []
for dirpath, dirnames, filenames in os.walk(SRC):
    rel = os.path.relpath(dirpath, SRC)
    if rel != '.':
        dirs.append(rel)
    for n in dirnames + filenames:
        p = os.path.join(dirpath, n)
        if os.path.islink(p):
            links.append((os.path.relpath(p, SRC), os.readlink(p)))
dirs.sort(); links.sort()

# symlink 的父目錄也要先建出來
for rel, _t in links:
    d = os.path.dirname(rel)
    if d and d not in dirs:
        dirs.append(d)
dirs = sorted(set(dirs))

out = []
out.append('# 由 tools/52_gen_rfs_mk.py 從原廠映像產生，不要手改。')
out.append('#')
out.append('# /vendor/rfs 是純目錄 + symlink 的樹（{} 個目錄、{} 條 symlink，沒有一般檔案），'.format(len(dirs), len(links)))
out.append('# blob 清單抽不到它 —— 產生器會跳過 symlink，空目錄也不會出現在檔案清單裡。')
out.append('# 缺了之後 tftp_server 會一直刷：')
out.append('#   tftp-server : mkdir failed: [/vendor/rfs/msm/mpss/readwrite] [No such file or directory]')
out.append('# 而 rfs 是 modem / adsp / slpi 讀寫 EFS 類檔案的路徑，RIL 會用到。')
out.append('')
out.append('TARGET_RFS_DIR := $(TARGET_OUT_VENDOR)/rfs')
out.append('')
out.append('define z01g-make-rfs')
out.append('\tmkdir -p ' + ' '.join('$(TARGET_RFS_DIR)/' + d for d in dirs))
for rel, target in links:
    out.append('\tln -sf {} $(TARGET_RFS_DIR)/{}'.format(target, rel))
out.append('endef')
out.append('')

with open(DST, 'w', encoding='utf-8', newline='\n') as fh:
    fh.write('\n'.join(out))
print(f'{DST}：{len(dirs)} 個目錄、{len(links)} 條 symlink')
