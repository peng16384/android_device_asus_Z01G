#!/usr/bin/env python3
"""
把 qcacld 的 hdd_ipa_fw_rejuvenate_send_msg() 改成 no-op。

為什麼：
    它用了 WLAN_FWR_SSR_BEFORE_SHUTDOWN 這個 enum ipa_wlan_event 的值，
    但這顆 kernel 的 include/uapi/linux/msm_ipa.h 裡沒有：
        wlan_hdd_ipa.c:7717:18: error: 'WLAN_FWR_SSR_BEFORE_SHUTDOWN' undeclared

    查過來源樹（LineageOS/android_kernel_oneplus_msm8998 lineage-16.0）——
    **它的 msm_ipa.h 也沒有這個值**，兩邊的 enum 一字不差。
    也就是那棵樹自己就不一致（qcacld 比平台標頭新），
    只是他們可能沒有實際編過這條路徑。

為什麼不改 msm_ipa.h：
    enum ipa_wlan_event 是 UAPI，而且後面的 enum ipa_wan_event 是接著
    IPA_WLAN_EVENT_MAX 繼續編號的：
        WAN_UPSTREAM_ROUTE_ADD = IPA_WLAN_EVENT_MAX,
    在中間加值會讓所有 WAN / ECM 事件的數值位移，
    可能破壞我們沿用的 ASUS IPA blob 的 ABI。

為什麼可以直接拿掉：
    這個函式只做一件事 —— 在 WLAN 韌體 SSR（子系統重啟）前送一則通知給 IPA。
    收這則通知的是 ipacm（IPA connection manager），而我們根本沒裝 ipacm
    （tools/40_check_services.sh 把它列在「服務有定義但執行檔不存在」），
    所以 WLAN 的 IPA offload 本來就不會運作。少送這則通知沒有實際影響。
    IPA offload 是資料路徑的加速功能，不是 Wi-Fi 連線的必要條件。
"""
import os
import io
import sys

F = (os.path.expanduser('~/zs551kl/kernel/msm-4.4/drivers/staging/qcacld-3.0/'
     'core/hdd/src/wlan_hdd_ipa.c'))

OLD = """void hdd_ipa_fw_rejuvenate_send_msg(hdd_context_t *hdd_ctx)
{
	struct hdd_ipa_priv *hdd_ipa;
	struct ipa_msg_meta meta;
	struct ipa_wlan_msg *msg;
	int ret;

	hdd_ipa = hdd_ctx->hdd_ipa;
	meta.msg_len = sizeof(*msg);
	msg = qdf_mem_malloc(meta.msg_len);
	if (!msg) {
		HDD_IPA_LOG(QDF_TRACE_LEVEL_DEBUG, "msg allocation failed");
		return;
	}
	meta.msg_type = WLAN_FWR_SSR_BEFORE_SHUTDOWN;
"""

NEW = """/*
 * Z01G：改成 no-op。
 *
 * 原本的實作用了 WLAN_FWR_SSR_BEFORE_SHUTDOWN，但這顆 kernel 的
 * include/uapi/linux/msm_ipa.h 的 enum ipa_wlan_event 裡沒有這個值
 * （來源樹 LineageOS/android_kernel_oneplus_msm8998 lineage-16.0 也沒有，
 *   兩邊的 enum 一字不差 —— 是那棵樹自己 qcacld 比平台標頭新）。
 *
 * 不在 msm_ipa.h 裡補這個值，是因為 enum ipa_wan_event 接著
 * IPA_WLAN_EVENT_MAX 繼續編號，加值會讓所有 WAN/ECM 事件位移，
 * 可能破壞我們沿用的 ASUS IPA blob 的 ABI。
 *
 * 拿掉沒有實際影響：這只是在 WLAN 韌體 SSR 前通知 IPA，
 * 而收通知的 ipacm 我們根本沒裝，WLAN 的 IPA offload 本來就不會運作。
 */
void hdd_ipa_fw_rejuvenate_send_msg(hdd_context_t *hdd_ctx)
{
	HDD_IPA_LOG(QDF_TRACE_LEVEL_DEBUG,
		    "fw rejuvenate msg skipped (no IPA event id on this kernel)");
}

#if 0	/* Z01G：保留原始實作供日後比對 */
static void hdd_ipa_fw_rejuvenate_send_msg_orig(hdd_context_t *hdd_ctx)
{
	struct hdd_ipa_priv *hdd_ipa;
	struct ipa_msg_meta meta;
	struct ipa_wlan_msg *msg;
	int ret;

	hdd_ipa = hdd_ctx->hdd_ipa;
	meta.msg_len = sizeof(*msg);
	msg = qdf_mem_malloc(meta.msg_len);
	if (!msg) {
		HDD_IPA_LOG(QDF_TRACE_LEVEL_DEBUG, "msg allocation failed");
		return;
	}
	meta.msg_type = WLAN_FWR_SSR_BEFORE_SHUTDOWN;
"""

TAIL_OLD = """	hdd_ipa->stats.num_send_msg++;
}

#endif /* IPA_OFFLOAD */"""

TAIL_NEW = """	hdd_ipa->stats.num_send_msg++;
}
#endif	/* Z01G：原始實作結束 */

#endif /* IPA_OFFLOAD */"""


def main():
    s = io.open(F, encoding='utf-8', newline='').read()
    if 'Z01G：改成 no-op' in s:
        print('  = 已經修補過'); return
    if OLD not in s:
        sys.exit('!!! 找不到要修補的函式（qcacld 版本不同？）')
    if TAIL_OLD not in s:
        sys.exit('!!! 找不到函式結尾')
    s = s.replace(OLD, NEW, 1).replace(TAIL_OLD, TAIL_NEW, 1)
    io.open(F, 'w', encoding='utf-8', newline='\n').write(s)
    print('  + wlan_hdd_ipa.c：hdd_ipa_fw_rejuvenate_send_msg 改成 no-op')


if __name__ == '__main__':
    main()
