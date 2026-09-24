#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 ASUS（Oreo）的 org.codeaurora.ims 改成能在 Android 9 上跑。

  python3 tools/99_patch_ims_smali.py <smali 目錄>

## 為什麼是改而不是重寫

Pie 把 Oreo 那套 IMS API 原地換成新版，舊的整組搬到 android.telephony.ims.compat.*，
而且保留了完整的轉接層（ImsResolver:303、ImsServiceControllerCompat、
MmTelFeatureCompatAdapter、ImsConfigCompatAdapter…）——就是為了這種 Oreo 時代的
IMS app。所以只要把類別參照指到新位置，再補幾個因為基底類別形狀變動而對不上的
方法就行。

## 改什麼

A. 類別搬家（compat 底下有形狀相同的）
B. Pie 完全沒有的類別 -> 指回 AIDL 的 Stub
C. 基底類別回傳型別變了 -> 改宣告的回傳型別
D. Pie 新增的 abstract 方法、改過的簽章、改過的建構式
E. ImsUtImpl 不再是 IImsUt -> 讓它真的實作那個介面
F. onBind 裡的 intent action 常數（manifest 那一半在 tools/100）
G. DDS 解析不到 phoneId 時退回 phone 0
H. 方法與欄位層的差異（tools/103 掃出來的）
I. turn on/off IMS 失敗時，過幾秒請框架整套重送

每一項都先驗證「原樣確實存在」，對不上就中止不寫檔。

## 驗證

改完之後一律用 tools/102（類別層）與 tools/103（方法與欄位層）
對著實際編出來的 framework 全掃。

⚠ 早期寫在這裡的「34 個 AIDL 簽章與 apk 完全相符」是錯的 ——
  那支比對腳本把 ImsReasonInfo 寫死成 com/android/ims/，等於把答案
  先假設進去。刷進去才看到 NoClassDefFoundError。見 A2 段。
"""
import os
import re
import sys

# ---- A. 類別搬家 + B. 指回 AIDL Stub ----------------------------------------
MOVE = {
    "Landroid/telephony/ims/ImsService;":
        "Landroid/telephony/ims/compat/ImsService;",
    "Landroid/telephony/ims/feature/MMTelFeature;":
        "Landroid/telephony/ims/compat/feature/MMTelFeature;",
    "Landroid/telephony/ims/feature/RcsFeature;":
        "Landroid/telephony/ims/compat/feature/RcsFeature;",
    "Landroid/telephony/ims/stub/ImsCallSessionImplBase;":
        "Landroid/telephony/ims/compat/stub/ImsCallSessionImplBase;",
    "Landroid/telephony/ims/stub/ImsConfigImplBase;":
        "Landroid/telephony/ims/compat/stub/ImsConfigImplBase;",
    "Landroid/telephony/ims/stub/ImsUtListenerImplBase;":
        "Landroid/telephony/ims/compat/stub/ImsUtListenerImplBase;",
    # Pie 完全沒有 ImsCallSessionListenerImplBase。Oreo 的它就是
    # IImsCallSessionListener.Stub 的 no-op 基底，而 ImsCallSessionListenerProxy
    # 實作了那支 AIDL 的全部 34 個方法（簽章逐一相符），直接繼承 Stub 即可。
    "Landroid/telephony/ims/stub/ImsCallSessionListenerImplBase;":
        "Lcom/android/ims/internal/IImsCallSessionListener$Stub;",

    # ---- A2. 資料類別從 com.android.ims 搬到 android.telephony.ims ----------
    # 這一類是刷進去才發現的（NoClassDefFoundError: Lcom/android/ims/ImsReasonInfo;
    # 讓 com.android.phone 反覆當掉 —— ims.apk 跑在 phone 行程裡）。
    #
    # ⚠ **不是整包改名**：Pie 只搬了資料類別，這些留在原地：
    #       com.android.ims.ImsException / ImsConfigListener / ImsConfig /
    #       ImsUtInterface / ImsManager（ims-common）
    #       以及整個 com.android.ims.internal.*（那些 AIDL 都還在）
    # 所以只能逐一列，不能用前綴取代。
    #
    # 這一批是 tools/102_check_dex_refs.py 對著實際編出來的 framework 掃出來的
    # —— 逐一查看比對會漏，對著產物全面掃才抓得齊。
    # 已確認沒有內部類別（Xxx$Yyy）也沒有點號形式的反射字串。
    "Lcom/android/ims/ImsCallForwardInfo;":
        "Landroid/telephony/ims/ImsCallForwardInfo;",
    "Lcom/android/ims/ImsCallProfile;":
        "Landroid/telephony/ims/ImsCallProfile;",
    "Lcom/android/ims/ImsConferenceState;":
        "Landroid/telephony/ims/ImsConferenceState;",
    "Lcom/android/ims/ImsExternalCallState;":
        "Landroid/telephony/ims/ImsExternalCallState;",
    "Lcom/android/ims/ImsReasonInfo;":
        "Landroid/telephony/ims/ImsReasonInfo;",
    "Lcom/android/ims/ImsSsData;":
        "Landroid/telephony/ims/ImsSsData;",
    "Lcom/android/ims/ImsSsInfo;":
        "Landroid/telephony/ims/ImsSsInfo;",
    "Lcom/android/ims/ImsStreamMediaProfile;":
        "Landroid/telephony/ims/ImsStreamMediaProfile;",
    "Lcom/android/ims/ImsSuppServiceNotification;":
        "Landroid/telephony/ims/ImsSuppServiceNotification;",
    # 這個是類別不是 AIDL：Pie 的 com/android/ims/internal 底下只剩
    # IImsVideoCallProvider.aidl，抽象類別搬到了 android.telephony.ims
    "Lcom/android/ims/internal/ImsVideoCallProvider;":
        "Landroid/telephony/ims/ImsVideoCallProvider;",
}

# 刻意不動 android/telephony/ims/stub/{ImsUtImplBase,ImsEcbmImplBase,
# ImsMultiEndpointImplBase}：Pie 原地還有同名類別，而且 compat MMTelFeature 的
# getUtInterface() 等回傳的正是它們（不是 AIDL 介面）。

# ---- C. 回傳型別改了的方法 ---------------------------------------------------
# ART 是用「名稱 + 完整 descriptor」派送的，descriptor 不同就不算覆寫 ——
# 基底的預設實作（回傳 null）會被呼叫，而且不會有任何錯誤訊息。
# 另外 Pie 的 *ImplBase 不再是 Binder stub，宣告回傳 AIDL 介面卻 return 一個
# ImplBase 子類，會在類別載入時被 verifier 擋下。兩個理由都指向同一個修法：
# 把宣告的回傳型別改成 Pie 要的那個。
RETYPE = [
    ("getEcbmInterface",
     "Lcom/android/ims/internal/IImsEcbm;",
     "Landroid/telephony/ims/stub/ImsEcbmImplBase;"),
    ("getMultiEndpointInterface",
     "Lcom/android/ims/internal/IImsMultiEndpoint;",
     "Landroid/telephony/ims/stub/ImsMultiEndpointImplBase;"),
    ("getUtInterface",
     "Lcom/android/ims/internal/IImsUt;",
     "Landroid/telephony/ims/stub/ImsUtImplBase;"),
]

# getConfigInterface 不一樣：compat MMTelFeature 還是回傳 IImsConfig，
# 但 compat/stub/ImsConfigImplBase 變成普通類別，IImsConfig 要跟它拿
# （getIImsConfig() 回傳內部的 ImsConfigStub）。所以只在 bridge 的 return 之前
# 多插一次呼叫。用正規表示式而不是整段比對 —— baksmali 會夾 .prologue / .line。
CFG_METHOD = re.compile(
    r"(\.method public bridge synthetic getConfigInterface\(\)"
    r"Lcom/android/ims/internal/IImsConfig;"
    r".*?->getConfigInterface\(\)Lorg/codeaurora/ims/ImsConfigImpl;\n"
    r"\n"
    r"    move-result-object v0\n)"
    r"(\n    return-object v0)",
    re.S)

CFG_INSERT = (
    "\n"
    "    # --- z01g: Pie 的 compat ImsConfigImplBase 是普通類別，"
    "IImsConfig 要跟它拿 ---\n"
    "    invoke-virtual {v0}, Landroid/telephony/ims/compat/stub/"
    "ImsConfigImplBase;->getIImsConfig()Lcom/android/ims/internal/IImsConfig;\n"
    "\n"
    "    move-result-object v0\n"
)

# ---- D. 新增 / 改過的方法與建構式 --------------------------------------------
# compat/feature/ImsFeature:191 public abstract void onFeatureReady();
# Oreo 沒有，不補就是 AbstractMethodError。補成 no-op —— Oreo 的行為本來就是
# 「沒有這個回呼」。（onFeatureRemoved apk 有；getBinder 在 compat MMTelFeature
# 是 final，都不用補。）
ONFEATUREREADY = """
# --- z01g: Pie 的 compat ImsFeature 多了這個 abstract 方法，Oreo 沒有 ---
.method public onFeatureReady()V
    .locals 0

    return-void
.end method
"""

# Pie : updateCallBarringForServiceClass(int cbType, int action, String[] barrList, int serviceClass)
# CAF : updateCallBarringForServiceClass(int cbType, int action, int serviceClass, String[] barrList)
UPDATECB = """
# --- z01g: Pie 的參數順序是 (cbType, action, barrList, serviceClass) ---
.method public updateCallBarringForServiceClass(II[Ljava/lang/String;I)I
    .locals 1

    invoke-virtual {p0, p1, p2, p4, p3}, Lorg/codeaurora/ims/ImsUtImpl;->updateCallBarringForServiceClass(III[Ljava/lang/String;)I

    move-result v0

    return v0
.end method
"""

# compat/stub/ImsConfigImplBase 的建構式從無參數變成 ImsConfigImplBase(Context)。
# ImsConfigImpl.<init> 的簽章是 (ImsServiceSub, ImsSenderRxr, Context) -> p3 是 Context。
CTOR_OLD = ("    invoke-direct {p0}, Landroid/telephony/ims/compat/stub/"
            "ImsConfigImplBase;-><init>()V")
CTOR_NEW = ("    # --- z01g: Pie 的 compat ImsConfigImplBase 建構式改吃 Context ---\n"
            "    invoke-direct {p0, p3}, Landroid/telephony/ims/compat/stub/"
            "ImsConfigImplBase;-><init>(Landroid/content/Context;)V")

# ---- E. ImsUtImpl 不再是 IImsUt ---------------------------------------------
# Oreo 的 ImsUtImplBase extends IImsUt.Stub，所以 ImsUtImpl 本身就是一個 IImsUt；
# ImsUtImplHandler 有 11 處把 AsyncResult.userObj（送出請求時塞進去的 this）
# check-cast 成 IImsUt，再交給 ImsUtListenerProxy。
# Pie 的 ImsUtImplBase 是普通類別，那些 cast 執行到就會 ClassCastException
# （verifier 不會擋，所以是執行期才炸，而且只在做補充服務查詢時）。
#
# 改那 11 處要處理 v33 這種超過 15 的暫存器（得換成 /range 形式），
# 不如讓 ImsUtImpl 真的實作那個介面 —— 它本來就有 IImsUt 的每一個方法
# （19 個，其中 updateCallBarringForServiceClass 由上面那段補齊），
# 只差 IInterface 的 asBinder()。
# ---- F. onBind 自己比對 intent action ----------------------------------------
# apk 的 ImsService.onBind() 不是無條件回傳 binder，它會先比字串：
#     const-string v0, "android.telephony.ims.ImsService"
#     if (!v0.equals(intent.getAction())) { Log.e("Invalid Intent action in onBind: " + ...); return null; }
# 我們把 manifest 的 action 換成 compat 版，**程式碼裡這個常數沒跟著換**，
# 於是框架綁得到服務、卻拿不到 binder：
#     E/QImsService: ImsService : Invalid Intent action in onBind:
#                    android.telephony.ims.compat.ImsService
# 症狀是 ImsResolver 一路正常（Binding ImsService... with features），
# QImsService 也起來了、也接上 vendor 的 IImsRadio，但 IMS 堆疊始終
# activeStacks=false、registered=2，最後 GsmCdmaPhone 判定
# imsPhone.getServiceState().getState()=1(OUT_OF_SERVICE) 就走 CS 撥出去。
#
# 改 manifest 就一定要一起改這裡 —— 兩邊是同一件事的兩半。
ACTION_OLD = 'const-string/jumbo v0, "android.telephony.ims.ImsService"'
ACTION_NEW = ('# --- z01g: manifest 的 action 換成 compat 版，這裡要一起換 ---\n'
              '    const-string/jumbo v0, "android.telephony.ims.compat.ImsService"')

# ---- G. IMS 堆疊永遠不會被啟用（DDS 解析的時序競態）--------------------------
# 症狀：一切都對了 —— ImsResolver 綁定、onServiceConnected、IMS 也真的向
# 電信商註冊成功（self-identity URI = sip:<門號>@ims.taiwanmobile.com）——
# 但 MMTEL 的 feature status 停在 0(NOT_AVAILABLE)，框架因此判定
#     imsPhone.getServiceState().getState()=1(OUT_OF_SERVICE)
# 而把通話交給 GsmCdmaPhone 走 CS。台灣 3G 已關台，於是「撥號中」然後掛斷。
#
# 條件鏈：
#   ImsServiceSub.onStackConfigChanged(activeStacks)
#       activeStacks[phoneId] 為 true 才 setFeatureState(STATE_READY)
#   ImsSubController.updateActiveImsStackForPhoneId(phoneId)
#       phoneId 無效就直接 return（"switchImsPhone: Invalid phoneId: 2147483647"）
#   ImsSubController.updateActiveImsStackForSubId(ddsSubId)
#       SubscriptionManager.getPhoneId(DDS) —— **這裡回了 INVALID**
#
# 為什麼會 INVALID：IMS 在開機約 30 秒時查詢，而 SubscriptionController
# 當下還沒就緒。dumpsys isub 的歷史直接證實：
#     [getActiveSubInfoList] Sub Controller not ready   （反覆）
#     [addSubInfoRecord] sSlotIndexToSubId.size=1 slotIndex=0 subId=1  ← 之後才加進去
#
# 為什麼不會自己好：app 走到這一段是因為
#     REQUEST_GET_IMS_SUB_CONFIG error: 6 (REQUEST_NOT_SUPPORTED)
#     -> [Multi-sim] Using RAF and DDS to decide IMS Sub
#     -> 兩個 stack 的 RAF 都是 multimode -> 註冊 ACTION_DDS_SWITCH_DONE 後 EXIT
# 而那個廣播是 **QTI 自家 telephony 擴充**發的。原廠把 qti-telephony-common
# 編進了 boot image（/system/framework 裡只是 304 bytes 的樁），我們用的是
# AOSP 的 telephony —— 所以那個事件在這個建置上永遠不會發生。
# app 內也沒有別的重試路徑（唯一的 OnSubscriptionsChangedListener 在
# QtiCarrierConfigHelper，只做 carrier config 快取）。
#
# 所以：解析不到就退回 phone 0。
#
# ⚠ 這是三個方案裡權衡後選的，另外兩個都更差：
#   - 改成單卡（persist.radio.multisim.config=ss）：等於關掉 SIM2，
#     而且原廠實機確實是 dsds，這是真的雙卡機。
#   - 拿掉 handleRafInfoChange 的「只做一次」守衛：沒有用，
#     因為開機後根本沒有東西會再呼叫 initSubscriptionStatus。
#
# ⚠ 已知限制：如果唯一的 SIM 插在**卡槽 2**，IMS 會綁到錯的 stack。
#   這台的卡槽 2 是與 microSD 共用的複合槽，實機目前插著記憶卡。
#   真的要雙卡並用時要回來重新處理這一段。
SUBID_ANCHOR = """    .line 376
    invoke-virtual {p0, v0}, Lorg/codeaurora/ims/ImsSubController;->updateActiveImsStackForPhoneId(I)V"""

SUBID_PATCH = """    # --- z01g: 解析不到 DDS 的 phoneId 就退回 phone 0（見檔頭 G）---
    invoke-static {v0}, Landroid/telephony/SubscriptionManager;->isValidPhoneId(I)Z

    move-result v1

    if-nez v1, :z01g_phoneid_ok

    const/4 v0, 0x0

    :z01g_phoneid_ok
    .line 376
    invoke-virtual {p0, v0}, Lorg/codeaurora/ims/ImsSubController;->updateActiveImsStackForPhoneId(I)V"""

# ---- H. 方法與欄位層的差異（tools/103 掃出來的）------------------------------
# 類別層修好之後還有一整類錯：類別在、方法或欄位不在。這種只有執行到那一行
# 才會爆，而每輪「改->編->刷->測」要 20 分鐘，所以改用 tools/103 全掃。
# 實際踩到的第一個：撥號成功之後 com.android.phone 反覆當掉
#     NoSuchMethodError: parseAndKeepRawInput(String,String)
#     at CountryCodeTableAsus.formatNumberAsus
#
# H1. libphonenumber 把第一個參數從 String 改成 CharSequence。
#     String 是 CharSequence，所以只改 descriptor 就好。
PARSE_OLD = ("Lcom/android/i18n/phonenumbers/PhoneNumberUtil;->parseAndKeepRawInput"
             "(Ljava/lang/String;Ljava/lang/String;)"
             "Lcom/android/i18n/phonenumbers/Phonenumber$PhoneNumber;")
PARSE_NEW = ("Lcom/android/i18n/phonenumbers/PhoneNumberUtil;->parseAndKeepRawInput"
             "(Ljava/lang/CharSequence;Ljava/lang/String;)"
             "Lcom/android/i18n/phonenumbers/Phonenumber$PhoneNumber;")

# H2. ImsSsData 的欄位在 Pie 沒有 m 前綴（CAF 的 Oreo 版有）。
#     這是 A2 那批類別搬家的連帶效應 —— 搬了類別，欄位名也要跟著對。
SSDATA_FIELDS = {
    "Landroid/telephony/ims/ImsSsData;->mServiceType:I":
        "Landroid/telephony/ims/ImsSsData;->serviceType:I",
    "Landroid/telephony/ims/ImsSsData;->mRequestType:I":
        "Landroid/telephony/ims/ImsSsData;->requestType:I",
    "Landroid/telephony/ims/ImsSsData;->mTeleserviceType:I":
        "Landroid/telephony/ims/ImsSsData;->teleserviceType:I",
    "Landroid/telephony/ims/ImsSsData;->mServiceClass:I":
        "Landroid/telephony/ims/ImsSsData;->serviceClass:I",
    "Landroid/telephony/ims/ImsSsData;->mResult:I":
        "Landroid/telephony/ims/ImsSsData;->result:I",
}

# H3. Pie 把這兩個類別的無參數建構式拿掉了，只剩帶參數的版本。
#     apk 的寫法是「建完再逐一設欄位」，所以用 0 / null 呼叫帶參數的版本，
#     語意完全相同。
#     直接在原地改會超過 invoke-direct 的 5 個暫存器上限（得動 .registers），
#     所以改成呼叫我們自己加的一個小工廠類別，原地只佔兩行。
COMPAT_CLASS = "org/codeaurora/ims/Z01GCompat.smali"

COMPAT_SMALI = """.class public Lorg/codeaurora/ims/Z01GCompat;
.super Ljava/lang/Object;
.source "Z01GCompat.smali"

# z01g 自己加的。Pie 移除了下面兩個類別的無參數建構式（CAF 的 Oreo 版本有），
# 而 apk 的用法是「建完再逐一設欄位」，所以用 0 / null 叫帶參數的版本即可。
# 放成靜態工廠是為了不動呼叫端的 .registers —— 原地展開會超過
# invoke-direct 的 5 個暫存器上限。

.method public static newImsSsData()Landroid/telephony/ims/ImsSsData;
    .locals 6

    const/4 v1, 0x0

    const/4 v2, 0x0

    const/4 v3, 0x0

    const/4 v4, 0x0

    const/4 v5, 0x0

    new-instance v0, Landroid/telephony/ims/ImsSsData;

    invoke-direct/range {v0 .. v5}, Landroid/telephony/ims/ImsSsData;-><init>(IIIII)V

    return-object v0
.end method

.method public static newImsSuppServiceNotification()Landroid/telephony/ims/ImsSuppServiceNotification;
    .locals 7

    const/4 v1, 0x0

    const/4 v2, 0x0

    const/4 v3, 0x0

    const/4 v4, 0x0

    const/4 v5, 0x0

    const/4 v6, 0x0

    new-instance v0, Landroid/telephony/ims/ImsSuppServiceNotification;

    invoke-direct/range {v0 .. v6}, Landroid/telephony/ims/ImsSuppServiceNotification;-><init>(IIIILjava/lang/String;[Ljava/lang/String;)V

    return-object v0
.end method
"""

# ---- I. 開機時 turn on IMS 失敗就不會再試 --------------------------------------
# 症狀：偶爾（實測是刷機後的第一次開機）開機後 VoLTE 沒起來，撥號退回 CS，
# 在 3G 已關台的地方就是「撥號中」然後掛斷 —— 與完全沒有 IMS 一模一樣。
#
#     ImsResolver: Received Carrier Config Changed for SlotId: 0
#     IFRequest : [0012]< REQUEST_SET_SERVICE_STATUS error: 2
#     IFRequest : [0016]< REQUEST_IMS_REG_STATE_CHANGE error: 2
#     ImsServiceSubHandler : Request turn on/off IMS failed
#
# ⚠ error 2 是 E_GENERIC_FAILURE，**不是** E_RADIO_NOT_AVAILABLE（那是 1）。
#   錯誤碼沒經過轉換（ImsRadioResponse -> removeFromQueueAndSendResponse ->
#   IFRequest.onError 一路原值），對照表是 ImsSenderRxr.errorIdToString。
#   一開始照 Android RIL 的慣例猜成 RADIO_NOT_AVAILABLE，寫進了文件 —— 錯的。
#
# 正常開機的時序（錄一次完整開機的 logcat -b all 對照）：
#     28.32  ImsRadio UNSOL_RADIO_STATE_CHANGED 2 (ON)
#     28.45  ImsServiceSub EVENT_RADIO_ON
#     28.56  feature status=2 (READY)
#     30.51  Carrier Config Changed -> updateImsServiceConfig(true) -> 全部成功
# 失敗那次 carrier config 比 feature 狀態變化晚了 11 秒，無線電幾乎一定已經 ON
# —— 是 modem 的 IMS 那一側還沒好，不是無線電沒開。
# 所以不能「等 EVENT_RADIO_ON 再送」：那個事件早就過了。
# （apk 自己的 EVENT_RADIO_ON 處理也只有 queryServiceStatus，不會重送設定。）
#
# 框架那邊送設定的時機只有：feature 變 READY（startListeningForCalls）、
# carrier config 變更、使用者改設定。失敗的結果對框架是看不見的
# （compat 的 turnOnIms 是 oneway），所以之後再也沒有觸發點。
#
# 修法：turn on/off 的回應失敗時，過 5×n 秒請框架自己把整套重送一次，
# 最多 8 次（累計 3 分鐘）；成功就歸零。
# apk 跑在 com.android.phone 行程裡，框架的 ImsManager 也在同一個行程，
# ImsManager.getInstance(ctx, phoneId) 拿到的就是框架那一個 —— 所以直接呼叫
# updateImsServiceConfig(true)，不必自己重組 SET_SERVICE_STATUS 那些請求，
# 送什麼、送不送 turn on，都照框架當下的判斷。
#
# 測試：真正的失敗重現不出來，所以留一個開關
#     adb shell setprop debug.z01g.ims_fakefail 2
# 會把接下來「計數 < 2」的成功當成失敗處理，走完整的重試路徑。
# debug.* 重開機就消失，沒設就完全不影響行為。
TURNON_ANCHOR = """    iget-object v5, v0, Landroid/os/AsyncResult;->exception:Ljava/lang/Throwable;

    if-eqz v5, :cond_38

    .line 1600
    const-string/jumbo v5, "Request turn on/off IMS failed\""""

TURNON_PATCH = """    iget-object v5, v0, Landroid/os/AsyncResult;->exception:Ljava/lang/Throwable;

    # --- z01g: 失敗就請框架過幾秒整套重送（見 tools/99 檔頭 I）---
    invoke-static {p0, v5}, Lorg/codeaurora/ims/Z01GCompat;->onImsTurnOnResult(Lorg/codeaurora/ims/ImsServiceSub$ImsServiceSubHandler;Ljava/lang/Throwable;)V

    if-eqz v5, :cond_38

    .line 1600
    const-string/jumbo v5, "Request turn on/off IMS failed\""""

RETRY_SMALI = """
# ---- z01g: turn on/off IMS 失敗的重試（見 tools/99 檔頭 I）----

.field private static sImsRetry:[I

.method public static onImsTurnOnResult(Lorg/codeaurora/ims/ImsServiceSub$ImsServiceSubHandler;Ljava/lang/Throwable;)V
    .locals 8

    iget-object v0, p0, Lorg/codeaurora/ims/ImsServiceSub$ImsServiceSubHandler;->this$0:Lorg/codeaurora/ims/ImsServiceSub;

    iget v1, v0, Lorg/codeaurora/ims/ImsServiceSub;->mPhoneId:I

    if-ltz v1, :done

    const/4 v2, 0x4

    if-ge v1, v2, :done

    sget-object v2, Lorg/codeaurora/ims/Z01GCompat;->sImsRetry:[I

    if-nez v2, :have_array

    const/4 v2, 0x4

    new-array v2, v2, [I

    sput-object v2, Lorg/codeaurora/ims/Z01GCompat;->sImsRetry:[I

    :have_array
    aget v3, v2, v1

    if-nez p1, :failed

    # 成功。測試開關：計數 < debug.z01g.ims_fakefail 的話當成失敗
    const-string v4, "debug.z01g.ims_fakefail"

    const/4 v5, 0x0

    invoke-static {v4, v5}, Landroid/os/SystemProperties;->getInt(Ljava/lang/String;I)I

    move-result v4

    if-lt v3, v4, :failed

    aput v5, v2, v1

    if-eqz v3, :done

    const-string v4, "Z01G-IMS"

    const-string v5, "turn on/off IMS succeeded after retry, counter reset"

    invoke-static {v4, v5}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    goto :done

    :failed
    const/16 v4, 0x8

    if-lt v3, v4, :retry

    const-string v4, "Z01G-IMS"

    const-string v5, "turn on/off IMS failed, giving up after 8 retries"

    invoke-static {v4, v5}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;)I

    goto :done

    :retry
    add-int/lit8 v3, v3, 0x1

    aput v3, v2, v1

    mul-int/lit16 v4, v3, 0x1388

    new-instance v6, Ljava/lang/StringBuilder;

    invoke-direct {v6}, Ljava/lang/StringBuilder;-><init>()V

    const-string v7, "turn on/off IMS failed on phone "

    invoke-virtual {v6, v7}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v6, v1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    const-string v7, ", retry "

    invoke-virtual {v6, v7}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v6, v3}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    const-string v7, "/8 in "

    invoke-virtual {v6, v7}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v6, v4}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    const-string v7, " ms"

    invoke-virtual {v6, v7}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v6}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v6

    const-string v7, "Z01G-IMS"

    invoke-static {v7, v6}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    invoke-static {v0}, Lorg/codeaurora/ims/ImsServiceSub;->-get0(Lorg/codeaurora/ims/ImsServiceSub;)Landroid/content/Context;

    move-result-object v7

    new-instance v6, Lorg/codeaurora/ims/Z01GCompat$ImsRetry;

    invoke-direct {v6, v7, v1}, Lorg/codeaurora/ims/Z01GCompat$ImsRetry;-><init>(Landroid/content/Context;I)V

    int-to-long v4, v4

    invoke-virtual {p0, v6, v4, v5}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z

    :done
    return-void
.end method
"""

RETRY_CLASS = "org/codeaurora/ims/Z01GCompat$ImsRetry.smali"

RETRY_CLASS_SMALI = """.class Lorg/codeaurora/ims/Z01GCompat$ImsRetry;
.super Ljava/lang/Object;
.source "Z01GCompat.smali"

# 見 tools/99 檔頭 I：請框架把 IMS 設定整套重送一次。

.implements Ljava/lang/Runnable;

.field private final mContext:Landroid/content/Context;

.field private final mPhoneId:I

.method constructor <init>(Landroid/content/Context;I)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lorg/codeaurora/ims/Z01GCompat$ImsRetry;->mContext:Landroid/content/Context;

    iput p2, p0, Lorg/codeaurora/ims/Z01GCompat$ImsRetry;->mPhoneId:I

    return-void
.end method

.method public run()V
    .locals 3

    iget-object v0, p0, Lorg/codeaurora/ims/Z01GCompat$ImsRetry;->mContext:Landroid/content/Context;

    iget v1, p0, Lorg/codeaurora/ims/Z01GCompat$ImsRetry;->mPhoneId:I

    invoke-static {v0, v1}, Lcom/android/ims/ImsManager;->getInstance(Landroid/content/Context;I)Lcom/android/ims/ImsManager;

    move-result-object v0

    if-eqz v0, :done

    const-string v1, "Z01G-IMS"

    const-string v2, "retry: ImsManager.updateImsServiceConfig(true)"

    invoke-static {v1, v2}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    const/4 v1, 0x1

    invoke-virtual {v0, v1}, Lcom/android/ims/ImsManager;->updateImsServiceConfig(Z)V

    :done
    return-void
.end method
"""

NEWINST = [
    ("Landroid/telephony/ims/ImsSsData;", "newImsSsData"),
    ("Landroid/telephony/ims/ImsSuppServiceNotification;",
     "newImsSuppServiceNotification"),
]

IMPLEMENTS = ".implements Lcom/android/ims/internal/IImsUt;"

ASBINDER = """
# --- z01g: 讓 ImsUtImpl 真的是一個 IImsUt（見檔頭 E）---
.method public asBinder()Landroid/os/IBinder;
    .locals 1

    invoke-virtual {p0}, Landroid/telephony/ims/stub/ImsUtImplBase;->getInterface()Lcom/android/ims/internal/IImsUt;

    move-result-object v0

    invoke-interface {v0}, Lcom/android/ims/internal/IImsUt;->asBinder()Landroid/os/IBinder;

    move-result-object v0

    return-object v0
.end method
"""


def read(p):
    with open(p, encoding="utf-8") as fh:
        return fh.read()


def write(p, s):
    with open(p, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(s)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    root = sys.argv[1]
    ims = os.path.join(root, "org", "codeaurora", "ims")
    files = [os.path.join(d, n) for d, _, ns in os.walk(root)
             for n in ns if n.endswith(".smali")]
    print("smali 檔 %d 個" % len(files))

    # ---- A + B ----
    counts = dict.fromkeys(MOVE, 0)
    for path in files:
        s = orig = read(path)
        for old, new in MOVE.items():
            if old in s:
                counts[old] += s.count(old)
                s = s.replace(old, new)
        if s != orig:
            write(path, s)
    print("")
    print("[A/B] 類別參照改寫")
    for k, v in counts.items():
        print("    %-58s %d 處" % (k, v))
    bad = [k for k, v in counts.items() if v == 0]
    if bad:
        sys.exit("!!! 這些一次都沒出現，與事前分析不符，中止：\n    " + "\n    ".join(bad))

    # ---- C ----
    print("")
    print("[C] 回傳型別")
    path = os.path.join(ims, "ImsServiceSub.smali")
    s = read(path)
    for name, old_ret, new_ret in RETYPE:
        pat = re.compile(r"^(\.method public (?:bridge synthetic )?%s\(\))%s$"
                         % (re.escape(name), re.escape(old_ret)), re.M)
        if not pat.search(s):
            sys.exit("!!! ImsServiceSub 裡找不到 %s()%s" % (name, old_ret))
        s = pat.sub(lambda m: m.group(1) + new_ret, s)
        print("    %s() -> %s" % (name, new_ret))
    if not CFG_METHOD.search(s):
        sys.exit("!!! getConfigInterface 的 bridge 內容與預期不同")
    s = CFG_METHOD.sub(lambda m: m.group(1) + CFG_INSERT + m.group(2), s, count=1)
    print("    getConfigInterface() 改成回傳 getIImsConfig()")

    # ---- D（ImsServiceSub 的部分）----
    if re.search(r"^\.method public onFeatureReady\(\)V$", s, re.M):
        sys.exit("!!! ImsServiceSub 已經有 onFeatureReady()V")
    s += ONFEATUREREADY
    write(path, s)
    print("")
    print("[D] 新增 / 改過的方法與建構式")
    print("    ImsServiceSub.onFeatureReady()V  (no-op)")

    # ---- D（ImsUtImpl 的簽章）+ E ----
    path = os.path.join(ims, "ImsUtImpl.smali")
    s = read(path)
    if not re.search(r"^\.method public updateCallBarringForServiceClass"
                     r"\(III\[Ljava/lang/String;\)I$", s, re.M):
        sys.exit("!!! ImsUtImpl 裡找不到 CAF 版的 updateCallBarringForServiceClass")
    if re.search(r"^\.method public updateCallBarringForServiceClass"
                 r"\(II\[Ljava/lang/String;I\)I$", s, re.M):
        sys.exit("!!! ImsUtImpl 已經有 Pie 簽章的版本")
    if IMPLEMENTS in s:
        sys.exit("!!! ImsUtImpl 已經 implements IImsUt")
    m = re.search(r"^\.super \S+$", s, re.M)
    if not m:
        sys.exit("!!! ImsUtImpl 找不到 .super")
    s = s[:m.end()] + "\n" + IMPLEMENTS + s[m.end():]
    s += UPDATECB + ASBINDER
    write(path, s)
    print("    ImsUtImpl.updateCallBarringForServiceClass(II[Ljava/lang/String;I)I")
    print("    ImsUtImpl implements IImsUt + asBinder()")

    # ---- D（ImsConfigImpl 的建構式）----
    path = os.path.join(ims, "ImsConfigImpl.smali")
    s = read(path)
    if CTOR_OLD not in s:
        sys.exit("!!! ImsConfigImpl 裡找不到無參數的 super 建構式呼叫")
    s = s.replace(CTOR_OLD, CTOR_NEW, 1)
    write(path, s)
    print("    ImsConfigImpl super ctor -> <init>(Landroid/content/Context;)V")

    # ---- F ----
    print("")
    print("[F] onBind 的 intent action 常數")
    hits = []
    for path in files:
        if ACTION_OLD in read(path):
            hits.append(path)
    if len(hits) != 1:
        sys.exit("!!! 預期整棵樹只有 1 處 onBind 的 action 常數，實際 %d 處：\n    %s"
                 % (len(hits), "\n    ".join(hits)))
    path = hits[0]
    s2 = read(path).replace(ACTION_OLD, ACTION_NEW, 1)
    write(path, s2)
    print("    %s" % os.path.relpath(path, root))

    # ---- G ----
    print("")
    print("[G] DDS 解析不到時退回 phone 0")
    path = os.path.join(root, "org", "codeaurora", "ims", "ImsSubController.smali")
    s3 = read(path)
    if SUBID_ANCHOR not in s3:
        sys.exit("!!! ImsSubController 裡找不到 updateActiveImsStackForSubId 的呼叫點")
    if s3.count(SUBID_ANCHOR) != 1:
        sys.exit("!!! 那個呼叫點出現 %d 次，不確定該改哪一個" % s3.count(SUBID_ANCHOR))
    if "z01g_phoneid_ok" in s3:
        sys.exit("!!! 已經改過了")
    write(path, s3.replace(SUBID_ANCHOR, SUBID_PATCH, 1))
    print("    ImsSubController.updateActiveImsStackForSubId")

    # ---- H ----
    print("")
    print("[H] 方法與欄位層（tools/103 掃出來的）")
    n_parse = n_field = 0
    for path in files:
        s4 = orig4 = read(path)
        if PARSE_OLD in s4:
            n_parse += s4.count(PARSE_OLD)
            s4 = s4.replace(PARSE_OLD, PARSE_NEW)
        for a, b in SSDATA_FIELDS.items():
            if a in s4:
                n_field += s4.count(a)
                s4 = s4.replace(a, b)
        if s4 != orig4:
            write(path, s4)
    if n_parse == 0:
        sys.exit("!!! 找不到 parseAndKeepRawInput 的舊簽章")
    if n_field == 0:
        sys.exit("!!! 找不到 ImsSsData 的 m 前綴欄位")
    print("    parseAndKeepRawInput -> CharSequence  %d 處" % n_parse)
    print("    ImsSsData 欄位去掉 m 前綴            %d 處" % n_field)

    write(os.path.join(root, COMPAT_CLASS.replace("/", os.sep)),
          COMPAT_SMALI + RETRY_SMALI)
    print("    新增 %s" % COMPAT_CLASS)
    for cls, factory in NEWINST:
        pat = re.compile(
            r"    new-instance (v[0-9]+), %s\n\n"
            r"    invoke-direct \{\1\}, %s-><init>\(\)V"
            % (re.escape(cls), re.escape(cls)))
        hit = 0
        for path in files:
            s5 = read(path)
            if not pat.search(s5):
                continue
            hit += len(pat.findall(s5))
            s5 = pat.sub(
                lambda m: ("    # --- z01g: Pie 沒有無參數建構式（見檔頭 H3）---\n"
                           "    invoke-static {}, Lorg/codeaurora/ims/Z01GCompat;->"
                           "%s()%s\n\n"
                           "    move-result-object %s" % (factory, cls, m.group(1))),
                s5)
            write(path, s5)
        if hit == 0:
            sys.exit("!!! 找不到 %s 的無參數 new-instance" % cls)
        print("    %-52s %d 處" % (factory, hit))

    # ---- I ----
    print("")
    print("[I] turn on/off IMS 失敗時請框架重送")
    path = os.path.join(ims, "ImsServiceSub$ImsServiceSubHandler.smali")
    s6 = read(path)
    if s6.count(TURNON_ANCHOR) != 1:
        sys.exit("!!! ImsServiceSubHandler 裡 turn on/off 回應那段出現 %d 次（預期 1）"
                 % s6.count(TURNON_ANCHOR))
    write(path, s6.replace(TURNON_ANCHOR, TURNON_PATCH, 1))
    # 用到的兩個 package 內部成員要真的存在（名字是 javac 產生的，換版就會變）
    sub = read(os.path.join(ims, "ImsServiceSub.smali"))
    for need in (".method static synthetic -get0(Lorg/codeaurora/ims/ImsServiceSub;)"
                 "Landroid/content/Context;",
                 ".field protected mPhoneId:I"):
        if need not in sub:
            sys.exit("!!! ImsServiceSub 裡找不到 %s" % need)
    if ".field final synthetic this$0:Lorg/codeaurora/ims/ImsServiceSub;" not in s6:
        sys.exit("!!! ImsServiceSubHandler 裡找不到 this$0")
    write(os.path.join(root, RETRY_CLASS.replace("/", os.sep)), RETRY_CLASS_SMALI)
    print("    ImsServiceSubHandler what=9 -> Z01GCompat.onImsTurnOnResult")
    print("    新增 %s" % RETRY_CLASS)

    print("")
    print("完成。")


if __name__ == "__main__":
    main()
