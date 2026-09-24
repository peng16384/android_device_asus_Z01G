#!/usr/bin/env python3
"""
在 qcacld 的 pld_snoc.h 加一層 icnss 舊版 API 的轉接。

為什麼：
    這個版本的 qcacld 假設 icnss 是「每個函式第一個參數都是 struct device *dev」
    的新版 API（CAF 在 2018 年改的，新標頭會定義 ICNSS_API_WITH_DEV）。
    ASUS 這棵 msm-4.4 的 icnss 是改版前的：
        icnss_ce_request_irq(unsigned int ce_id, ...)        ← 我們的
        icnss_ce_request_irq(struct device *dev, ce_id, ...)  ← qcacld 要的
    錯誤長這樣：
        pld_snoc.h:155:9: error: too many arguments to function 'icnss_ce_request_irq'

    而且 qcacld 還用到三個我們完全沒有的函式：
        icnss_block_shutdown / icnss_is_fw_down / icnss_is_rejuvenate

為什麼改 qcacld 而不是改 icnss：
    icnss 是目前**正常運作**的驅動 —— 實機 dmesg 已經有
        icnss: Platform driver probed successfully
        icnss: QMI Server Connected / WLAN FW is ready: 0xd87
    不想動它。pld（platform driver layer）本來就是 qcacld 用來吸收平台差異的
    薄包裝層，把轉接放在這裡最合適；之後若把 icnss 更新到新版 API，
    只要把這段拿掉即可。

    另一個選項是照抄 OnePlus 的 icnss.c，但它會 #include <linux/project_info.h>
    —— OnePlus 自己的裝置資訊功能，我們沒有那個標頭。

做法：
    用函式式巨集把新版呼叫轉成舊版。C 的巨集不會遞迴展開（同名的內層出現
    不會再被展開），所以 `#define f(a, b) f(b)` 是合法且只展開一次的。

    缺的三個補成 inline stub：
      icnss_is_fw_down()     -> !icnss_is_fw_ready()   我們的標頭有 is_fw_ready
      icnss_is_rejuvenate()  -> false                  沒有對應概念，回 false 安全
      icnss_block_shutdown() -> no-op                  只是在關鍵操作期間擋 SSR，
                                                       最壞情況是罕見的競態
"""
import io
import os
import sys

F = (os.path.expanduser('~/zs551kl/kernel/msm-4.4/drivers/staging/qcacld-3.0/'
     'core/pld/src/pld_snoc.h'))

ANCHOR = """#ifdef CONFIG_PLD_SNOC_ICNSS
#include <soc/qcom/icnss.h>
#endif
"""

SHIM = """#ifdef CONFIG_PLD_SNOC_ICNSS
#include <soc/qcom/icnss.h>

/*
 * Z01G：ASUS 這棵 msm-4.4 的 icnss 是舊版 API —— 函式第一個參數沒有
 * struct device *dev（CAF 後來才加的，新標頭會定義 ICNSS_API_WITH_DEV）。
 * 這裡把新版呼叫轉接回舊版，順便補上三個我們沒有的函式。
 *
 * 之所以轉接而不是改 icnss：那是目前正常運作的驅動
 * （dmesg: icnss: WLAN FW is ready: 0xd87），不想動它。
 * pld 這一層本來就是用來吸收平台差異的。
 * 之後 icnss 若更新到新版 API，把這整段拿掉即可。
 *
 * 函式式巨集同名轉接是合法的 —— C 的巨集不會遞迴展開。
 */
#ifndef ICNSS_API_WITH_DEV

#define icnss_ce_request_irq(dev, ce_id, handler, flags, name, ctx) \\
	icnss_ce_request_irq(ce_id, handler, flags, name, ctx)
#define icnss_ce_free_irq(dev, ce_id, ctx)	icnss_ce_free_irq(ce_id, ctx)
#define icnss_enable_irq(dev, ce_id)		icnss_enable_irq(ce_id)
#define icnss_disable_irq(dev, ce_id)		icnss_disable_irq(ce_id)
#define icnss_get_ce_id(dev, irq)		icnss_get_ce_id(irq)
#define icnss_get_irq(dev, ce_id)		icnss_get_irq(ce_id)
#define icnss_get_soc_info(dev, info)		icnss_get_soc_info(info)
#define icnss_set_fw_log_mode(dev, mode)	icnss_set_fw_log_mode(mode)
#define icnss_is_qmi_disable(dev)		icnss_is_qmi_disable()
#define icnss_wlan_enable(dev, cfg, mode, ver)	\\
	icnss_wlan_enable(cfg, mode, ver)
#define icnss_wlan_disable(dev, mode)		icnss_wlan_disable(mode)

/* 舊版 icnss 沒有這三個 */
static inline bool icnss_is_fw_down(void)
{
	/* 舊版只有 is_fw_ready，語意剛好相反 */
	return !icnss_is_fw_ready();
}

static inline bool icnss_is_rejuvenate(void)
{
	/* 舊版沒有 firmware rejuvenate 的概念，回 false 是安全的預設 */
	return false;
}

static inline void icnss_block_shutdown(bool status)
{
	/*
	 * 新版用它在關鍵操作期間擋住 SSR。舊版沒有對應機制，
	 * 做成 no-op —— 最壞情況是罕見的競態，不影響一般連線。
	 */
}

#endif /* !ICNSS_API_WITH_DEV */
#endif
"""


def main():
    s = io.open(F, encoding='utf-8', newline='').read()
    if 'Z01G：ASUS 這棵 msm-4.4 的 icnss' in s:
        print('  = 已經修補過')
        return
    if ANCHOR not in s:
        sys.exit('!!! 找不到 pld_snoc.h 的 icnss include 區塊')
    io.open(F, 'w', encoding='utf-8', newline='\n').write(s.replace(ANCHOR, SHIM, 1))
    print('  + pld_snoc.h：加入 icnss 舊版 API 轉接（11 個巨集 + 3 個 stub）')


if __name__ == '__main__':
    main()
