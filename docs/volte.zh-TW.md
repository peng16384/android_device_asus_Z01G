# VoLTE：把 Oreo 時代的 IMS app 搬到 Android 9

> English: [volte.md](volte.md)

把 ASUS ZenFone 4 Pro 原廠的 `ims.apk`（對 Android 8.0 的 IMS API 編的、
odex 過、而且 dex 被 quicken 過）改成能在 LineageOS 16.0 上跑。

**這是整個專案最有轉移價值的部分。** 除了檔案路徑之外，這裡沒有一件事是
ZS551KL 專屬的——任何 vendor 出貨了舊版 CAF/Qualcomm `org.codeaurora.ims`
的機器，都會按同樣的順序踩到同樣的問題。

---

## 為什麼非做不可

台灣的 3G 已經關台，而且關台的國家越來越多。
`dumpsys telephony.registry` 顯示 CS 網域是**掛在 LTE 上**的：

```
mVoiceRegState=0(IN_SERVICE)  mRilVoiceRadioTechnology=14(LTE)
CS regState=HOME accessNetworkTechnology=LTE
```

也就是電路交換語音根本到不了，只剩 VoLTE。

處理之前的症狀：撥號畫面停在「撥號中」約 32 秒，然後自己掛斷。

```
E ImsManager: Connector: Retrying getting ImsService...
I Telecom   : CallsManager: setCallState DIALING -> DISCONNECTED
```

vendor 那一側本來就是好的——`imsqmidaemon` 與 `imsdatadaemon` 都在跑、
`vendor.ims.QMI_DAEMON_STATUS=1`。缺的是 **Android 這一側**：
AOSP 根本沒有 IMS 實作，那部分是 vendor 的東西。

## 為什麼原廠的 apk 不能直接用

`/system/app/ims/ims.apk` 只有 34,598 bytes，裡面沒有 `classes.dex`：

```
oat/arm64/ims.odex   148,176
oat/arm64/ims.vdex   932,616     <- 真正的 dex 在這裡
```

三個各自獨立的問題：

1. **它是 odex 過的。** dex 在旁邊的 `.vdex` 裡。
2. **dex 被 quicken 過。** `quickening_info_size_ = 82396`，約 4200 個
   quickened opcode，它們的運算元是 vtable 偏移量，跟當初那顆 **Oreo boot
   image** 綁死。不還原就直接用，會在第一個 quickened 指令上爆掉。
3. **它是對 Oreo 的 IMS API 編的。** Android 9 把那一整套搬到了
   `android.telephony.ims.compat.*`，原地換成新的。

第三點是最有意思的，也正是這件事可行的原因：**Google 保留了完整的相容層**，
就是為了這種 Oreo 時代的 IMS app。`ImsResolver` 會同時搜尋兩種介面，而
`ImsServiceControllerCompat`、`MmTelFeatureCompatAdapter`、
`ImsConfigCompatAdapter`、`ImsRegistrationCompatAdapter` 全都在。
所以這是**搬位置**，不是重寫。

## 流程

[`tools/101_build_ims_apk.sh`](../tools/101_build_ims_apk.sh)
對著裝置自己的原廠映像跑完整套：

```
vdexExtractor -f                  還原 quicken（驗證過：差 60,275 bytes）
baksmali
tools/99_patch_ims_smali.py       改 API 參照位置（見下）
smali
tools/100_patch_axml_string.py    改 manifest 的 intent action
signapk                           用 platform key 重簽
```

manifest 那一步**只重建 binary XML 的字串池**，不走 apktool。
元素與屬性都是用**索引**參照字串，所以換掉一條字串再修好偏移量，
其餘位元組完全不動——影響範圍遠小於把整包資源重新編碼。

用 platform key 重簽不是可選的：它宣告了
`sharedUserId="android.uid.phone"`，簽名必須與 `com.android.phone` 相同。

## `tools/99` 改了什麼

| | |
|---|---|
| **A** | 6 個類別搬到 `compat` 底下（形狀逐一確認過相同）|
| **A2** | 9 個**資料類別**從 `com.android.ims` 搬到 `android.telephony.ims` |
| **B** | `ImsCallSessionListenerImplBase` 在 Pie 不存在 → 指回 AIDL 的 `Stub` |
| **C** | `getUt`/`getEcbm`/`getMultiEndpointInterface` 的回傳型別改成 Pie 的 `*ImplBase`；`getConfigInterface` 改成回傳 `getIImsConfig()` |
| **D** | 補 `onFeatureReady()` no-op；`updateCallBarringForServiceClass` 的參數順序；`ImsConfigImpl` 的 super 建構式改吃 `Context` |
| **E** | `ImsUtImpl` 補 `implements IImsUt` + `asBinder()` |
| **F** | `onBind()` 裡的 intent action 字串常數 |
| **G** | DDS 的 phoneId 解析不到時退回 phone 0 |
| **H** | 方法層與欄位層的差異 |
| **I** | turn on/off IMS 失敗時，過幾秒請框架把整套設定重送一次 |

其中兩項值得特別注意，因為它們**錯了也不會出聲**：

**A2 不是整包改名。** Pie 只搬了資料類別（`ImsReasonInfo`、`ImsCallProfile`、
`ImsSsData` …），而 `ImsException`、`ImsConfigListener`、`ImsManager`
與整個 `com.android.ims.internal.*` 留在原地。用前綴取代會把留下來的那些弄壞。

**C 錯了是看不見的。** ART 是用「名稱 + 完整 descriptor」派送的。
descriptor 不同就不算覆寫——基底的預設實作（回傳 `null`）會被呼叫，
而且任何地方都不會有錯誤訊息。再加上 Pie 的 `*ImplBase` 已經不是 Binder
stub，宣告回傳 AIDL 介面卻 return 一個 `ImplBase` 子類，
會在類別載入時被 verifier 擋下。

## 四輪各自卡在哪

每一輪都是「編 → 刷 → 測」約 20 分鐘，所以查得太窄的代價很高。

### 第一輪——類別層

```
java.lang.NoClassDefFoundError: Failed resolution of: Lcom/android/ims/ImsReasonInfo;
Process: com.android.phone
```

真正的教訓是關於方法，不是關於那個類別。我當時是用**自己手寫的型別對應表**
去比對 AIDL 簽章，而表裡把 `ImsReasonInfo` 寫死成 `com/android/ims/`
——等於把假設寫進了檢查工具，然後把它的輸出當成印證。
它回報「34 個簽章完全相符」，聽起來很篤定，實際上毫無意義。

改成 [`tools/102_check_dex_refs.py`](../tools/102_check_dex_refs.py)：
讀裝置 `BOOTCLASSPATH` 上每個 jar 的 `class_defs`，
再拿目標 dex 的所有外部型別參照去比對。一次就列出全部 10 個。

### 第二輪——app 自己也在比對 action

```
E QImsService: ImsService : Invalid Intent action in onBind:
               android.telephony.ims.compat.ImsService
```

`onBind()` 不是無條件回傳 binder，它會先把 intent action 跟一個字串常數比對。
manifest 改了，程式碼裡那一份沒改——**兩邊是同一件事的兩半**。

從外面看一切正常：`ImsResolver` 綁定了服務、`QImsService` 起來了、
也接上了 `vendor.qti.hardware.radio.ims@1.0::IImsRadio`
——而 IMS 堆疊就是起不來。

### 第三輪——已經向電信商註冊成功，但 feature 仍然不可用

```
QImsService: VOLTE ims registered
QImsService: self-identity host URI = sip:<門號>@ims.<電信商>
ImsServiceController: notifyImsFeatureStatus: slot=0, feature=1, status=0
```

IMS 是真的向電信商的網路註冊成功了。但框架要 feature 到
`status=2 (READY)` 才會用它，而到那裡的條件鏈是：

```
ImsServiceSub.onStackConfigChanged(activeStacks)
    activeStacks[phoneId] 為 true 才 setFeatureState(STATE_READY)
ImsSubController.updateActiveImsStackForPhoneId(phoneId)
    phoneId 無效就直接 return
ImsSubController.updateActiveImsStackForSubId(ddsSubId)
    SubscriptionManager.getPhoneId(DDS) -> INVALID
```

`getPhoneId()` 回 INVALID 是因為 IMS 在開機約 30 秒時查詢，
而 `SubscriptionController` 當下還沒就緒。`dumpsys isub` 的歷史直接證實：

```
[getActiveSubInfoList] Sub Controller not ready              （反覆）
[addSubInfoRecord] sSlotIndexToSubId.size=1 slotIndex=0 subId=1   <- 之後才加進去
```

**而且它不會自己好。** app 會走到這一段是因為
`REQUEST_GET_IMS_SUB_CONFIG` 回 `error: 6`（這顆 modem 不支援），
於是退回「用 RAF 與 DDS 決定」；兩個 stack 都是 multimode，
它就註冊 `ACTION_DDS_SWITCH_DONE` 然後結束。而那個廣播是
**QTI 自家 telephony 擴充**發的——原廠把 `qti-telephony-common` 編進了
boot image（`/system/framework` 裡只是 304 bytes 的樁），
我們用的是 AOSP 的 telephony。那個事件永遠不會到，app 內也沒有別的重試路徑。

這件事值得推廣：**移植缺的可能不只是檔案，還有「誰會發那個事件」。**
這種缺口在 SELinux denial、在缺檔清單裡都看不出來，只能讀程式碼才會發現。

修法：解析不到就退回 phone 0。另外兩個方案權衡後都更差——
改成單卡等於關掉 SIM2（原廠實機確實是 `dsds`）；
拿掉 `handleRafInfoChange` 的「只做一次」守衛沒有用，
因為開機後根本沒有東西會再呼叫它。

> **已知限制：** 唯一的 SIM 如果插在**卡槽 2**，IMS 會綁到錯的 stack。
> 單卡請插卡槽 1。

### 第四輪——方法層與欄位層

電話**真的撥出去了**——然後 `com.android.phone` 開始反覆當掉：

```
NoSuchMethodError: parseAndKeepRawInput(String,String)
at org.codeaurora.ims.CountryCodeTableAsus.formatNumberAsus
```

（libphonenumber 把第一個參數改成了 `CharSequence`。）

`tools/102` 只比對類別，抓不到這一類。新增
[`tools/103_check_dex_methods.py`](../tools/103_check_dex_methods.py)：
解析 `method_ids` 與 `field_ids`，再沿著 classpath 上每個被參照類別的
父類別與介面往上找。一次列出 6 個方法 + 5 個欄位，
而不是一輪刷機抓一個。

其中 3 個刻意不處理：`ImsManager` 的 `getImsServiceStatus`、`isConnected`、
`isOpened` 只在 `QtiImsExtManager`（給 QTI/ASUS 自家 App 的擴充 API）
裡用到，這個建置沒有裝會呼叫它的東西。真有東西踩到，
錯誤訊息會直接點名這三個。

## 通話通了之後才浮現的兩個音訊問題

兩個是同一個根源。為了修藍牙 A2DP，`/vendor/etc/audio/` 底下 ASUS 那份
split-A2DP 的 `audio_policy_configuration.xml` 被排除，於是退到
`/vendor/etc/` 那份。而那份其實是 **AOSP 的通用範本**——
ASUS 留在樹裡從來沒用過，因為在 Android 9 的搜尋順序
（`/odm/etc` → `/vendor/etc/audio` → `/vendor/etc` → `/system/etc`）裡
`/vendor/etc/audio/` 優先。

| 症狀 | 原因 |
|---|---|
| 擴音關不掉 | `<attachedDevices>` 沒有 `Earpiece`，於是 `AudioManager.getDevices()` 從來不回報 `TYPE_BUILTIN_EARPIECE`，Telecom 把聽筒路由整個停用 |
| 接著藍牙耳機講電話，聲音還是從手機出來 | 三個 BT SCO 的 devicePort 有宣告，但**沒有任何 `<route>` 以它們為 sink** |

[`tools/104_patch_audio_policy.py`](../tools/104_patch_audio_policy.py)
照 ASUS 真正使用的那份補上 `Earpiece`、`Telephony Rx`/`Tx`，
以及一個 `BT SCO All` 的 sink 與對應的輸出 route。

> **「檔案在、內容也是原廠的」不等於「那是這台實際讀的那一份」。**
> 同一個設定檔在搜尋路徑上有多份時，排除了優先的那份之後，
> 退到的那份未必被驗證過。

## 開機時序——turn on 失敗之後不會再試

通話打通之後，還是有一次開機（刷機後的第一次）VoLTE 沒起來，
開啟序列的每個請求都失敗：

```
ImsResolver: Received Carrier Config Changed for SlotId: 0
IFRequest : [0012]< REQUEST_SET_SERVICE_STATUS error: 2
IFRequest : [0016]< REQUEST_IMS_REG_STATE_CHANGE error: 2
ImsServiceSubHandler : Request turn on/off IMS failed
```

症狀與完全沒有 IMS 一模一樣：撥號退回 CS，在 3G 已關台的地方就是
「撥號中」然後掛斷。

**`error: 2` 是 `E_GENERIC_FAILURE`，不是 `RADIO_NOT_AVAILABLE`（那是 `1`）。**
我一開始把它讀成 `RADIO_NOT_AVAILABLE`——是照 Android RIL 的慣例用猜的，
沒去查 app 自己的對照表（`ImsSenderRxr.errorIdToString`）。
錯誤碼從 HAL 的回應一路原值傳到 log，沒有轉換。

這對修法有決定性的影響。錄一次**正常**開機，順序是：

```
28.32  ImsRadio UNSOL_RADIO_STATE_CHANGED 2 (ON)
28.45  ImsServiceSub EVENT_RADIO_ON
28.56  feature status=2 (READY)
30.51  Carrier Config Changed -> 送出整套設定 -> 全部成功
```

失敗那次，carrier config 比 feature 狀態變化晚了 11 秒才到，
當時無線電幾乎一定已經開了，是 modem 的 IMS 那一側還沒準備好。
「等無線電開了再送」沒有用：那個事件早就過了。
（app 自己的 `EVENT_RADIO_ON` 處理本來也只做 `queryServiceStatus`。）

之後不會再試，是因為框架看不到這個失敗：compat 的 `turnOnIms()` 是單向呼叫（oneway）。
框架只在三種時機送設定：feature 變成 READY、carrier config 變更、使用者改設定。

**修法（I 段）：** turn on/off 的回應失敗時，等 5×n 秒後呼叫
`ImsManager.getInstance(context, phoneId).updateImsServiceConfig(true)`，
最多 8 次（累計 3 分鐘），成功就把計數歸零。
app 跑在 `com.android.phone` 裡，跟框架是同一個行程，
拿到的就是框架自己那一個 `ImsManager`。它送的內容跟開機時完全一樣，
app 不必自己重組那些請求。

真正的失敗沒辦法隨時重現，所以留了一個測試開關：

```bash
adb shell setprop debug.z01g.ims_fakefail 2     # 計數 < 2 時，把成功當成失敗
adb shell cmd phone ims enable -s 0             # 觸發一次 turn on
adb logcat -s Z01G-IMS
```

```
turn on/off IMS failed on phone 0, retry 1/8 in 5000 ms
retry: ImsManager.updateImsServiceConfig(true)       <- 3 個 SET_SERVICE_STATUS + turn on
turn on/off IMS failed on phone 0, retry 2/8 in 10000 ms
retry: ImsManager.updateImsServiceConfig(true)
turn on/off IMS succeeded after retry, counter reset
```

設成 `99` 的話，第 8 次之後會放棄。`debug.*` 屬性重開機就消失；沒設的話完全不影響行為。

> **已知邊角：** 放棄之後計數會停在 8，要等下一次真的成功才歸零。
> 這段期間如果別的觸發點又失敗，就不會重試。
> 要連續失敗超過 3 分鐘才會進到這個狀態。

## 搭配的設定

三個地方，缺一不可：

```
overlay      config_ims_package = org.codeaurora.ims       （AOSP 預設：空字串）
             config_dynamic_bind_ims = true                （AOSP 預設：false）
system.prop  persist.dbg.{ims_volte_enable,volte_avail_ovr,vt_avail_ovr,
             wfc_avail_ovr}、persist.radio.calls.on.ims
prebuilt/    BUILD_PREBUILT + PRESIGNED
```

`config_dynamic_bind_ims` 比看起來重要。維持預設的 `false` 時，
`ImsResolver` 走靜態路徑，綁的是 `ImsServiceControllerStaticCompat`
——而它找的是 **8.0 之前**那種註冊在 ServiceManager、名字叫 `"ims"` 的
`IImsService`。我們這顆是 8.0 式、用 intent action 宣告的 `Service`，
靜態路徑找不到它。

apk 進 `PRODUCT_COPY_FILES` 會被 `build/make/core/Makefile` 明文擋掉，
所以走 `BUILD_PREBUILT` 模組。

## 結果

```
activeStacks[0]=true
notifyImsFeatureStatus: slot=0, feature=1, status=2
ImsPhoneCallTracker: handleFeatureCapabilityChanged: isVolteEnabled=true
```

通話接得通、音訊路由正確、擴音可以切換、藍牙耳機也能接通話音訊。
開機時 turn on 失敗會自動重試（I 段）。

## 可以帶走的五件事

1. **不要用自己寫的對應表去驗證自己的假設。** 要對著**真的會跑的產物**檢查
   ——也就是實際編出來的 framework。
2. **三個層次各自會壞**：類別、方法、欄位，分別產生
   `NoClassDefFoundError`、`NoSuchMethodError`、`NoSuchFieldError`，
   而且三者都只在執行到那一行時才出現。
3. **改了 manifest？去看程式碼裡有沒有對應的字串常數。**
4. **移植缺的可能是一個事件來源，不只是檔案。**
5. **錯誤碼要去產生它的程式碼裡查。** 照相鄰的慣例猜，把「modem 的 IMS 那側
   還沒好」誤讀成「無線電沒開」，差點就寫出一個等待早已發生過的事件的修法。
