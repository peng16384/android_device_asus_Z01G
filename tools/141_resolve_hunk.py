#!/usr/bin/env python3
"""解一個 diff3 衝突區塊（tools/140 合併出來的）。

    python3 141_resolve_hunk.py <檔案> <第幾個衝突，從 1 起算> ours|theirs|both|both-rev|@<內容檔>

  ours       保留我們的（HEAD）
  theirs     採用 CIP 的
  both       ours 接著 theirs
  both-rev   theirs 接著 ours
  @檔案       用那個檔案的內容取代整個區塊（自己寫的合併結果）

區塊的格式固定是 tools/140 產生的：<<<<<<< HEAD / ||||||| <base> / ======= / >>>>>>> theirs。
解完印出剩下的衝突數。
"""
import sys


def hunks(lines):
    out, i = [], 0
    while i < len(lines):
        if lines[i].startswith('<<<<<<< '):
            a = i
            b = next(j for j in range(a + 1, len(lines)) if lines[j].startswith('||||||| '))
            c = next(j for j in range(b + 1, len(lines)) if lines[j] == '=======\n')
            d = next(j for j in range(c + 1, len(lines)) if lines[j].startswith('>>>>>>> '))
            out.append((a, b, c, d))
            i = d + 1
        else:
            i += 1
    return out


def main():
    path, idx, mode = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    lines = open(path, encoding='utf-8', errors='surrogateescape').readlines()
    hs = hunks(lines)
    if not 1 <= idx <= len(hs):
        sys.exit('!!! %s 只有 %d 個衝突' % (path, len(hs)))
    a, b, c, d = hs[idx - 1]
    ours, theirs = lines[a + 1:b], lines[c + 1:d]
    if mode == 'ours':
        new = ours
    elif mode == 'theirs':
        new = theirs
    elif mode == 'both':
        new = ours + theirs
    elif mode == 'both-rev':
        new = theirs + ours
    elif mode.startswith('@'):
        new = open(mode[1:], encoding='utf-8').readlines()
    else:
        sys.exit('!!! 不認得的方式：' + mode)
    lines[a:d + 1] = new
    open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='').writelines(lines)
    print('%s：剩 %d 個衝突' % (path, len(hunks(lines))))


if __name__ == '__main__':
    main()
