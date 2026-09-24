# VoLTE: porting an Oreo IMS app to Android 9

> 中文版：[volte.zh-TW.md](volte.zh-TW.md)

How the ASUS ZenFone 4 Pro's stock `ims.apk` — built against the Android 8.0
IMS API, odexed, and quickened — was made to work on LineageOS 16.0.

**This is the most transferable part of this project.** Nothing here is
specific to the ZS551KL beyond file paths: any device whose vendor ships a
CAF/Qualcomm `org.codeaurora.ims` from an older Android release hits the same
problems in the same order.

---

## Why this was mandatory

3G has been shut down in Taiwan, and in a growing number of countries.
`dumpsys telephony.registry` showed the CS domain registered **on LTE**:

```
mVoiceRegState=0(IN_SERVICE)  mRilVoiceRadioTechnology=14(LTE)
CS regState=HOME accessNetworkTechnology=LTE
```

Circuit-switched voice is therefore unreachable: VoLTE or nothing.

Symptom before this work: the dialer sat at "Dialing" for ~32 seconds and hung
up by itself.

```
E ImsManager: Connector: Retrying getting ImsService...
I Telecom   : CallsManager: setCallState DIALING -> DISCONNECTED
```

The vendor side was already healthy — `imsqmidaemon` and `imsdatadaemon`
running, `vendor.ims.QMI_DAEMON_STATUS=1`. What was missing was the **Android
side**: AOSP contains no IMS implementation at all. That part is the vendor's.

## Why the stock APK cannot be used as-is

`/system/app/ims/ims.apk` is 34,598 bytes and contains no `classes.dex`:

```
oat/arm64/ims.odex   148,176
oat/arm64/ims.vdex   932,616     <- the real dex lives here
```

Three separate problems:

1. **It is odexed.** The dex is in the `.vdex` companion file.
2. **The dex is quickened.** `quickening_info_size_ = 82396` — roughly 4200
   quickened opcodes whose operands are vtable offsets bound to the *Oreo boot
   image*. Extracting the dex without unquickening yields something that
   crashes on the first quickened instruction.
3. **It targets the Oreo IMS API.** Android 9 moved that entire API to
   `android.telephony.ims.compat.*` and put a new one in its place.

Problem 3 is the interesting one, and it is also why this is tractable:
**Google kept a complete compatibility layer** precisely for Oreo-era IMS
apps. `ImsResolver` searches for both interfaces, and
`ImsServiceControllerCompat`, `MmTelFeatureCompatAdapter`,
`ImsConfigCompatAdapter` and `ImsRegistrationCompatAdapter` all exist. So this
is a *relocation* job, not a rewrite.

## The pipeline

[`tools/101_build_ims_apk.sh`](../tools/101_build_ims_apk.sh) runs the whole
thing against the device's own stock image:

```
vdexExtractor -f                  unquicken (verified: 60,275 bytes differ)
baksmali
tools/99_patch_ims_smali.py       relocate API references (below)
smali
tools/100_patch_axml_string.py    rewrite the manifest's intent action
signapk                           re-sign with the platform key
```

The manifest patcher rebuilds **only the binary XML string pool** instead of
running the APK through apktool. Elements and attributes reference strings by
*index*, so replacing one string and fixing the offsets leaves every other byte
untouched — a far smaller blast radius than re-encoding all resources.

Re-signing with the platform key is not optional: the app declares
`sharedUserId="android.uid.phone"` and must carry the same signature as
`com.android.phone`.

## What `tools/99` changes

| | |
|---|---|
| **A** | 6 classes relocated under `compat` (shapes verified identical) |
| **A2** | 9 **data classes** moved from `com.android.ims` to `android.telephony.ims` |
| **B** | `ImsCallSessionListenerImplBase` does not exist in Pie → point at the AIDL `Stub` |
| **C** | `getUt`/`getEcbm`/`getMultiEndpointInterface` return types changed to Pie's `*ImplBase`; `getConfigInterface` now returns `getIImsConfig()` |
| **D** | `onFeatureReady()` added as a no-op; `updateCallBarringForServiceClass` argument order; `ImsConfigImpl`'s super constructor now takes a `Context` |
| **E** | `ImsUtImpl` given `implements IImsUt` + `asBinder()` |
| **F** | the intent action string constant inside `onBind()` |
| **G** | fall back to phone 0 when the DDS phone id cannot be resolved |
| **H** | method- and field-level differences |
| **I** | when turning IMS on/off fails, ask the framework to resend the whole configuration a few seconds later |

Two of these deserve attention because they fail *silently*:

**A2 is not a blanket rename.** Pie moved the data classes (`ImsReasonInfo`,
`ImsCallProfile`, `ImsSsData`, …) but left `ImsException`,
`ImsConfigListener`, `ImsManager` and the whole of `com.android.ims.internal.*`
where they were. A prefix substitution breaks the ones that stayed.

**C is invisible when wrong.** ART dispatches on *name + full descriptor*. If
the descriptor differs, the method simply does not override the base — the
base's default implementation (returning `null`) runs, with no error anywhere.
Additionally, Pie's `*ImplBase` classes are no longer Binder stubs, so
declaring an AIDL interface return type while returning an `ImplBase` subclass
is rejected by the verifier at class load.

## The four rounds, and what each one taught

Each round is a 20-minute build → flash → test cycle, so a narrow diagnosis is
expensive.

### Round 1 — class level

```
java.lang.NoClassDefFoundError: Failed resolution of: Lcom/android/ims/ImsReasonInfo;
Process: com.android.phone
```

The real lesson is about method, not about that class. I had been comparing
AIDL signatures with a **hand-written type mapping** in which `ImsReasonInfo`
was hard-coded to `com/android/ims/` — my assumption was written into the
checker, and I then read its output as confirmation. It reported "all 34
signatures match exactly", which sounded authoritative and meant nothing.

Replaced by [`tools/102_check_dex_refs.py`](../tools/102_check_dex_refs.py):
read the `class_defs` of every jar on the device's `BOOTCLASSPATH`, then check
every external type reference in the target dex against that set. It listed
all 10 missing classes in one pass.

### Round 2 — the app checks the action itself

```
E QImsService: ImsService : Invalid Intent action in onBind:
               android.telephony.ims.compat.ImsService
```

`onBind()` does not return the binder unconditionally; it compares the intent
action against a string constant first. The manifest had been changed and the
code had not — **two halves of the same thing**.

Everything looked healthy from the outside: `ImsResolver` bound the service,
`QImsService` started, it reached
`vendor.qti.hardware.radio.ims@1.0::IImsRadio` — and the IMS stack still never
came up.

### Round 3 — registered with the carrier, feature still unavailable

```
QImsService: VOLTE ims registered
QImsService: self-identity host URI = sip:<msisdn>@ims.<carrier>
ImsServiceController: notifyImsFeatureStatus: slot=0, feature=1, status=0
```

IMS had genuinely registered with the carrier's network. But the framework
only uses MMTEL once the feature reaches `status=2 (READY)`, and the chain is:

```
ImsServiceSub.onStackConfigChanged(activeStacks)
    setFeatureState(STATE_READY) only if activeStacks[phoneId]
ImsSubController.updateActiveImsStackForPhoneId(phoneId)
    returns immediately if the phone id is invalid
ImsSubController.updateActiveImsStackForSubId(ddsSubId)
    SubscriptionManager.getPhoneId(DDS) -> INVALID
```

`getPhoneId()` returned invalid because IMS queries it roughly 30 seconds into
boot, while `SubscriptionController` is not ready. `dumpsys isub` history shows
it directly:

```
[getActiveSubInfoList] Sub Controller not ready              (repeatedly)
[addSubInfoRecord] sSlotIndexToSubId.size=1 slotIndex=0 subId=1   <- only afterwards
```

**And it never recovers.** The app reaches that path because
`REQUEST_GET_IMS_SUB_CONFIG` returns `error: 6` (unsupported by this modem),
so it falls back to deciding by RAF and DDS; with two multimode stacks it
registers for `ACTION_DDS_SWITCH_DONE` and exits. That broadcast is sent by
**QTI's telephony extension** — the stock ROM compiles `qti-telephony-common`
into its boot image (the jar in `/system/framework` is a 304-byte stub), while
this build uses AOSP telephony. The event can never arrive, and the app has no
other retry path.

Worth generalising: **a port can be missing not just files, but whoever was
going to send an event.** That kind of gap is invisible in SELinux denials and
in missing-blob reports; you only find it by reading the code.

Fix: fall back to phone 0. Two alternatives were considered and rejected —
switching the device to single-SIM disables SIM 2 (the stock device really is
`dsds`), and removing the "run once" guard in `handleRafInfoChange` achieves
nothing, because nothing calls back into it after boot.

> **Limitation:** if the only SIM is in **slot 2**, IMS binds the wrong stack.
> Put a single SIM in slot 1.

### Round 4 — method and field level

The call **went out** — and then `com.android.phone` crashed repeatedly:

```
NoSuchMethodError: parseAndKeepRawInput(String,String)
at org.codeaurora.ims.CountryCodeTableAsus.formatNumberAsus
```

(libphonenumber changed the first parameter to `CharSequence`.)

`tools/102` only compares classes. Added
[`tools/103_check_dex_methods.py`](../tools/103_check_dex_methods.py): parse
`method_ids` and `field_ids`, then walk the superclass and interface chain of
each referenced class on the classpath. It listed 6 methods and 5 fields in one
pass, instead of one per flash cycle.

Three are deliberately left unfixed: `ImsManager.getImsServiceStatus`,
`isConnected` and `isOpened` are reached only from `QtiImsExtManager`, an
extension API for QTI/ASUS applications that this build does not ship. If
anything ever calls it, the failure names those methods explicitly.

## Two audio consequences that surfaced only after calls worked

Both share a root cause. To fix Bluetooth A2DP, ASUS's split-A2DP
`audio_policy_configuration.xml` under `/vendor/etc/audio/` was excluded, which
falls back to the copy in `/vendor/etc/`. That copy turns out to be **AOSP's
generic template** — ASUS left it in the tree and never used it, because
`/vendor/etc/audio/` takes priority in Android 9's search order
(`/odm/etc` → `/vendor/etc/audio` → `/vendor/etc` → `/system/etc`).

| Symptom | Cause |
|---|---|
| Speakerphone could not be turned off | `<attachedDevices>` had no `Earpiece`, so `AudioManager.getDevices()` never reported `TYPE_BUILTIN_EARPIECE` and Telecom disabled the earpiece route entirely |
| Call audio stayed on the phone with a BT headset connected | the three BT SCO device ports are declared, but **no `<route>` has them as a sink** |

[`tools/104_patch_audio_policy.py`](../tools/104_patch_audio_policy.py) adds
`Earpiece` and `Telephony Rx`/`Tx` to `attachedDevices`, plus a `BT SCO All`
sink with an output route, following what ASUS's real configuration does.

> **A file being present, and being the stock one, does not mean it is the one
> your device actually reads.** When a config has several candidate locations,
> excluding the one with priority can leave you on a copy nobody ever validated.

## Boot timing — a failed turn-on is never retried

Once calls worked, VoLTE still failed to come up on one boot (the first boot
after flashing). Every request of the turn-on sequence failed:

```
ImsResolver: Received Carrier Config Changed for SlotId: 0
IFRequest : [0012]< REQUEST_SET_SERVICE_STATUS error: 2
IFRequest : [0016]< REQUEST_IMS_REG_STATE_CHANGE error: 2
ImsServiceSubHandler : Request turn on/off IMS failed
```

The symptom is identical to having no IMS at all: the call falls back to CS
and, where 3G has been shut down, sits at "Dialing" and hangs up.

**`error: 2` is `E_GENERIC_FAILURE`, not `RADIO_NOT_AVAILABLE`** (that is `1`).
I first read it as `RADIO_NOT_AVAILABLE`, assuming the Android RIL convention
instead of reading the app's own table (`ImsSenderRxr.errorIdToString`). The
code travels unchanged from the HAL response to the log line.

That mattered for the fix. A recording of a *good* boot shows the order:

```
28.32  ImsRadio UNSOL_RADIO_STATE_CHANGED 2 (ON)
28.45  ImsServiceSub EVENT_RADIO_ON
28.56  feature status=2 (READY)
30.51  Carrier Config Changed -> whole configuration sent -> all succeed
```

In the failing boot, carrier config arrived 11 seconds after the feature
status changed, so the radio was almost certainly already on. It was the
modem's IMS side that was not ready yet. "Wait for the radio, then send" would
not have helped: that event had already passed. (The app's own
`EVENT_RADIO_ON` handler only calls `queryServiceStatus` anyway.)

Nothing tries again because the framework cannot see the failure. The compat
`turnOnIms()` is one-way. The framework sends the configuration only when the
feature becomes ready, when carrier config changes, or when the user changes
a setting.

**Fix (section I):** when the turn-on/off response fails, wait 5 × n seconds and
call `ImsManager.getInstance(context, phoneId).updateImsServiceConfig(true)`.
Retry at most 8 times (3 minutes in total); a success resets the counter. The
app runs inside `com.android.phone`, the same process as the framework, so this
is the framework's own `ImsManager` instance. It resends exactly what it would
at boot, and the app does not have to rebuild the requests itself.

A real failure could not be reproduced on demand, so there is a test switch:

```bash
adb shell setprop debug.z01g.ims_fakefail 2     # treat successes as failures while counter < 2
adb shell cmd phone ims enable -s 0             # trigger a turn-on
adb logcat -s Z01G-IMS
```

```
turn on/off IMS failed on phone 0, retry 1/8 in 5000 ms
retry: ImsManager.updateImsServiceConfig(true)       <- 3× SET_SERVICE_STATUS + turn-on
turn on/off IMS failed on phone 0, retry 2/8 in 10000 ms
retry: ImsManager.updateImsServiceConfig(true)
turn on/off IMS succeeded after retry, counter reset
```

With `99` it gives up after the eighth retry. `debug.*` properties vanish on
reboot; unset, the switch has no effect.

> **Known edge:** after giving up, the counter stays at 8 until a real success.
> If another trigger fails in that window, it is not retried. Reaching that
> state takes more than three minutes of continuous failure.

## Wiring

Three places, all required:

```
overlay      config_ims_package = org.codeaurora.ims       (AOSP default: empty)
             config_dynamic_bind_ims = true                (AOSP default: false)
system.prop  persist.dbg.{ims_volte_enable,volte_avail_ovr,vt_avail_ovr,
             wfc_avail_ovr}, persist.radio.calls.on.ims
prebuilt/    BUILD_PREBUILT + PRESIGNED
```

`config_dynamic_bind_ims` matters more than it looks. With the default
`false`, `ImsResolver` takes the static path, which binds
`ImsServiceControllerStaticCompat` — and that looks for the **pre-8.0**
`IImsService` registered in ServiceManager under the name `"ims"`. This app is
the 8.0-style `Service` declared by intent action, so the static path cannot
find it.

APKs are rejected in `PRODUCT_COPY_FILES` by `build/make/core/Makefile`, hence
the `BUILD_PREBUILT` module.

## Result

```
activeStacks[0]=true
notifyImsFeatureStatus: slot=0, feature=1, status=2
ImsPhoneCallTracker: handleFeatureCapabilityChanged: isVolteEnabled=true
```

Calls connect, audio routes correctly, the speaker toggle works, and Bluetooth
headsets carry call audio. A failed turn-on at boot is retried (section I).

## What to take away

1. **Do not verify an assumption with a mapping you wrote yourself.** Check
   against the artefact that will actually run — the built framework.
2. **Three levels fail independently**: class, method, field. They produce
   `NoClassDefFoundError`, `NoSuchMethodError` and `NoSuchFieldError`, and all
   three appear only when that line executes.
3. **Changing a manifest? Look for the matching string constant in the code.**
4. **A port can be missing an event source, not just a file.**
5. **Look up an error code in the code that produced it.** Guessing from a
   neighbouring convention turned "the modem's IMS side is not ready" into
   "the radio is off", and that would have led to a fix waiting for an event
   that had already happened.
