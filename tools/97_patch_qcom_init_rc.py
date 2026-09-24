#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把原廠 vendor/etc/init/hw/init.qcom.rc 補上兩行缺少的 `group`，產生我們自己的版本。

  python3 tools/97_patch_qcom_init_rc.py

為什麼需要這支：
  ASUS 那份 init.qcom.rc 的 qcom-sh 與 qcom-post-boot 都只有 `user root`，
  **沒有 group 行** —— 也就是 gid 0、零個附加群組。
  但那兩支腳本要碰的檔案不是 root 的：

    /data/vendor/radio/copy_complete   660 radio:radio    <- init.qcom.sh 寫（RIL 等這個旗標）
    /data/vendor/radio/db_check_done   660 radio:radio
    /data/vendor/radio/modem_config/   770 radio:radio    <- 首次開機要把 MCFG 抄進去
    .../cpufreq/scaling_min_freq       664 system:system  <- post_boot 寫
    /sys/power/wake_lock               660 radio:wakelock <- post_boot 寫

  root 不是 owner、gid 0 也不在群組裡 -> 每一次都要 CAP_DAC_OVERRIDE，
  而 AOSP 的 domain.te:1385 把 dac_override 限制在 dac_override_allowed 內，
  qti_init_shell 不在裡面 -> enforcing 下全部失敗。

  這不是政策該放寬，是服務的 group 設錯。對照 LineageOS 16.0 的
  OnePlus msm8998 樹（同 SoC）：

    service qcom-sh          ... group root system radio
    service qcom-post-boot   ... group root system wakelock graphics

  ASUS 這份是 Oreo 時代的，那兩行從來沒有過。

實測後果（2026-09-24，enforcing）：
  copy_complete 停在 0（init 在 post-fs-data 寫的初始值）。
  libril-qc-qmi-1.so 裡有這個字串 —— 那是 QCRIL 的 modem config 模組在等的旗標。
"""
import io, os, re, sys

SRC = "/mnt/zs_system/vendor/etc/init/hw/init.qcom.rc"
DST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                   "rootdir/vendor/etc/init/hw/init.qcom.rc")

# service 名稱 -> 要插入的 group 行（照 OnePlus msm8998 樹）
WANT = {
    "qcom-sh":        "    group root system radio",
    "qcom-post-boot": "    group root system wakelock graphics",
}

# 額外一行（**這條不是上游有的，是我們加的**）：
#   init.qcom.sh 第一件事是 `cat /data/vendor/radio/ver_info.txt` 比對版本，
#   相同就跳過整個 MCFG 重抄。但那個檔是 0400 radio:radio ——
#   它是上一輪 `cp /firmware/verinfo/ver_info.txt`（來源 0444）在 umask 077
#   之下建出來的，group 位元被砍光。加了 group radio 也讀不到。
#   讀不到 -> prev_version_info 為空 -> 每次開機都 rm -rf + 重抄整個
#   modem_config（數 MB），而且中途若有一步被擋，會留下不完整的 modem_config
#   —— 比現在更糟。補 group 讀取位元讓比對成立，整段就正常跳過。
#   放在 post-fs-data、緊接在 vendor 自己那三行 copy_complete 的
#   write/chown/chmod 後面（那幾行證明這個位置本來就是做這件事的地方）。
ANCHOR = "    chmod 0660 /data/vendor/radio/copy_complete"
EXTRA = "    chmod 0640 /data/vendor/radio/ver_info.txt"


def patch(lines):
    out, done, i = [], {}, 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = re.match(r"^service\s+(\S+)\s", line)
        if m and m.group(1) in WANT:
            name = m.group(1)
            # 掃這個 service 區塊，確認本來沒有 group，並找 user 行的位置
            j, has_group, user_at = i + 1, False, None
            while j < len(lines) and (lines[j].startswith((" ", "\t")) or not lines[j].strip()):
                s = lines[j].strip()
                if s.startswith("group "):
                    has_group = True
                if s.startswith("user "):
                    user_at = j
                j += 1
            if has_group:
                print("  %-16s 已經有 group 行，跳過" % name)
            elif user_at is None:
                sys.exit("!!! %s 區塊裡找不到 user 行，格式與預期不同，中止" % name)
            else:
                # 把 user 之前的行照抄，然後在 user 後面插入 group
                for k in range(i + 1, user_at + 1):
                    out.append(lines[k])
                out.append(WANT[name])
                print("  %-16s 插入：%s" % (name, WANT[name].strip()))
                done[name] = True
                i = user_at
        elif line == ANCHOR:
            out.append(EXTRA)
            print("  %-16s 插入：%s" % ("(post-fs-data)", EXTRA.strip()))
            done["__extra__"] = True
        i += 1
    return out, done


def main():
    if not os.path.exists(SRC):
        sys.exit("!!! 找不到 %s —— 先跑 sudo bash tools/07_mount_system.sh" % SRC)

    with io.open(SRC, encoding="utf-8", errors="surrogateescape") as fh:
        lines = fh.read().split("\n")
    print("原始：%s（%d 行）" % (SRC, len(lines)))

    out, done = patch(lines)

    missing = [n for n in list(WANT) + ["__extra__"] if n not in done]
    if missing:
        sys.exit("!!! 這些 service 沒被改到：%s —— 不寫檔" % ", ".join(missing))
    n_add = len(WANT) + 1
    if len(out) != len(lines) + n_add:
        sys.exit("!!! 行數變化不對（%d -> %d，應該 +%d），不寫檔"
                 % (len(lines), len(out), n_add))

    # 驗證：除了新增的那幾行，其餘必須逐行相同
    new_lines = set(WANT.values()) | {EXTRA}
    added = [l for l in out if l in new_lines]
    rest = [l for l in out if l not in new_lines]
    if len(added) != n_add or rest != [l for l in lines if l not in new_lines]:
        sys.exit("!!! 除了新增的那幾行之外還有別的差異，不寫檔")

    os.makedirs(os.path.dirname(DST), exist_ok=True)
    with io.open(DST, "w", encoding="utf-8", errors="surrogateescape", newline="\n") as fh:
        fh.write("\n".join(out))
    print("寫出：%s（%d 行，+%d）" % (os.path.normpath(DST), len(out), n_add))


if __name__ == "__main__":
    main()
