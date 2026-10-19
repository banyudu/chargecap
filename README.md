# ChargeCap

ChargeCap is a tiny menu-bar utility that uses the Mac firmware's built-in charge-limit keys instead of a polling loop. It is a free, local alternative to subscription charge-limiting features.

## Requirements

- Apple Silicon Mac
- macOS 26 or later
- The `bfF0` / `bfD0` / `bfE0` firmware charge-limit keys. These were first observed on recent Apple Silicon firmware.

Building from source also requires Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
```

## How it works

The app writes the same firmware-managed keys used by macOS 26-era battery limiting:

| Key | Purpose |
| --- | --- |
| `bfF0` | Limit activation (`0x00` off, `0x02` on) |
| `bfD0` | Upper charge percentage (little-endian `ui32`) |
| `bfE0` | Lower charge percentage (little-endian `ui32`) |

The write sequence is deactivate, write upper, write lower, activate. Every operation is read back and verified. If verification fails, the helper deactivates the limit again. ChargeCap never uses `CHIE`/`CH0I` and never cuts adapter power.

The root helper is installed through `SMAppService` and is only reachable over XPC by ChargeCap's signed app and Control Center extension.

## Build and install

```bash
make build
make install
```

`make install` copies the signed app to `/Applications`. Launch it once, then approve **ChargeCapHelper** in **System Settings → General → Login Items & Extensions**.

The helper must be installed from an app in `/Applications`; running the app from Xcode's DerivedData is not sufficient for `SMAppService`.

Set your own signing identity with `make build SIGN_IDENTITY="Developer ID Application: ..."` if the default certificate lookup does not match.

## Add the Control Center switch

1. Open Control Center.
2. Choose **Edit Controls**.
3. Add the **Charge Cap** switch.

macOS does not allow an app to place a Control Center control automatically, so this one-time step is required.

The switch toggles the cap using the limit selected in the menu-bar app. Changing the limit while the cap is active applies the new value immediately.

## Troubleshooting

- **Helper unavailable**: open Login Items & Extensions and approve ChargeCapHelper. If the app was moved after approval, remove and reinstall it.
- **Firmware keys not present**: this machine does not expose the firmware limit API. The app intentionally does not fall back to adapter cutting or unsafe SMC keys.
- **AlDente or another battery limiter is installed**: quit it and remove its helper before testing ChargeCap. Two tools writing charging keys can fight each other.
- **Readback mismatch**: run the root CLI to inspect state:

```bash
sudo /Applications/ChargeCap.app/Contents/MacOS/ChargeCapHelper state
```

To test the firmware path directly:

```bash
sudo /Applications/ChargeCap.app/Contents/MacOS/ChargeCapHelper set 80
sudo /Applications/ChargeCap.app/Contents/MacOS/ChargeCapHelper off
```

## Safety notes

This project is not affiliated with Apple or AlDente. It changes undocumented SMC keys, which can change how the battery charges. Use it at your own risk and keep a way to restore the default state through `ChargeCapHelper off`.
