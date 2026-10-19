# ChargeCap

ChargeCap is a tiny settings app and Control Center switch for limiting how
high your MacBook battery charges. It is a free, local alternative to
subscription charge-limiting features and does not run a polling loop.

ChargeCap has no menu-bar item and no Dock icon. Open
`/Applications/ChargeCap.app` from Finder or Spotlight whenever you want to
change the limit. The Control Center switch keeps working while the settings
app is closed because the privileged helper runs as a daemon.

## Requirements

- Apple Silicon Mac
- macOS 26 or later
- One of these charge-limit backends:
  - The native macOS charge limit (System Settings → Battery → Charge Limit),
    which offers **80%, 85%, 90%, and 95%**. This is the fallback on macOS
    27-era firmware where the SMC keys are gated behind an Apple-private
    entitlement.
  - The `bfF0` / `bfD0` / `bfE0` firmware charge-limit keys, available on
    firmware that still permits them. This backend accepts any value from 50%
    to 100% and provides a lower hysteresis threshold.

Building from source also requires Xcode 26 or later and
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
```

## Backends

ChargeCap probes the firmware keys first and falls back to the native macOS
limit when they are unavailable or return `kIOReturnNotPrivileged`.

### Native macOS limit

On current firmware, Apple gates `bfF0` / `bfD0` / `bfE0` behind the private
`com.apple.private.iokit.soc-limit` entitlement even for root. The same limit
is still available through `PowerUIAgent`, which is the path System Settings
uses. ChargeCap drives it through `PowerUI.framework`'s private
`PowerUISmartChargeClient` class.

- Supported limits: **80%, 85%, 90%, 95%** (the list is read from macOS).
- No lower limit: macOS decides when charging resumes.
- No private entitlement is required.
- Values below 80% are snapped up to 80%; the battery is never charged above
  the requested value.

This path is what makes ChargeCap work on macOS 27 without paying for another
app.

### Firmware limit

On firmware where the keys are still accessible, ChargeCap writes:

| Key | Purpose |
| --- | --- |
| `bfF0` | Limit activation (`0x00` off, `0x02` on) |
| `bfD0` | Upper charge percentage (little-endian `ui32`) |
| `bfE0` | Lower charge percentage (little-endian `ui32`) |

The write sequence is deactivate, write upper, write lower, activate. Every
operation is read back and verified. If verification fails, the helper
deactivates the limit again. ChargeCap never uses `CHIE`/`CH0I` and never cuts
adapter power.

## Architecture

- `ChargeCap` — settings window and helper installation.
- `ChargeCapControl` — Control Center toggle (`ControlWidgetToggle`).
- `ChargeCapHelper` — root helper installed with `SMAppService.daemon`. It
  exposes the limit over XPC and only accepts connections from ChargeCap's
  signed app and control extension.
- `Helper/PowerUIBridge.m` — runtime bridge to `PowerUI.framework`.
- `Helper/FirmwareChargeLimit.swift` — firmware SMC backend.
- `Helper/NativeChargeLimit.swift` — macOS native backend.

## Build and install

```bash
make build
make install
```

`make install` copies the signed app to `/Applications`. Launch it once, then
approve **ChargeCapHelper** in **System Settings → General → Login Items &
Extensions**.

The helper must be installed from an app in `/Applications`; running the app
from Xcode's DerivedData is not sufficient for `SMAppService`.

Set your own signing identity with
`make build SIGN_IDENTITY="Developer ID Application: ..."` if the default
certificate lookup does not match.

## Add the Control Center switch

1. Open Control Center.
2. Choose **Edit Controls**.
3. Add the **Charge Cap** switch.

macOS does not allow an app to place a Control Center control automatically, so
this one-time step is required.

The switch toggles the cap using the limit selected in the settings app.
Changing the limit while the cap is active applies the new value immediately.

## Command-line testing

The helper also runs as a CLI:

```bash
/Applications/ChargeCap.app/Contents/MacOS/ChargeCapHelper state
/Applications/ChargeCap.app/Contents/MacOS/ChargeCapHelper set 80
/Applications/ChargeCap.app/Contents/MacOS/ChargeCapHelper off
```

`state` reports the active backend:

```json
{
  "active": true,
  "availableLimits": [80, 85, 90, 95],
  "backend": "native",
  "supported": true,
  "upper": 80
}
```

The CLI persists its configuration under `/Library/Application Support/ChargeCap`,
so run it with `sudo` when you want the setting to survive a helper restart.

## Troubleshooting

- **Helper unavailable**: open Login Items & Extensions and approve
  ChargeCapHelper. If the app was moved after approval, remove and reinstall it.
- **Charge limiting unavailable**: neither the firmware keys nor the native
  macOS limit is exposed on this Mac.
- **AlDente or another battery limiter is installed**: quit it and remove its
  helper before testing ChargeCap. Two tools writing the same limit can fight
  each other.
- **Readback mismatch**: inspect the current state with the CLI.

## Safety notes

This project is not affiliated with Apple or AlDente. It uses a private
framework interface and, on older firmware, undocumented SMC keys. Use it at
your own risk and keep a way to restore the default state with
`ChargeCapHelper off` or System Settings → Battery.
