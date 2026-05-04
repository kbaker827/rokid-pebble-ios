# Rokid Pebble Hub


> **🔵 Connectivity Update — May 2025**
> The glasses connection has been migrated from **raw TCP sockets** to
> **Bluetooth via the Rokid AI glasses SDK** (`pod 'RokidSDK' ~> 1.10.2`).
> No Wi-Fi port forwarding is needed. See **SDK Setup** below.

iOS app that bridges live data from multiple sources to both **Rokid AR glasses** (TCP) and a **Pebble watch** (BLE/PPOGATT) simultaneously.

```
Tempest Hub  ──UDP :50222──▶ ┐
Snapmaker U1 ──HTTP :8080──▶ ├─ iPhone (RokidPebble) ──Bluetooth/RokidSDK──▶ Rokid Glasses
                              └─────────────BLE (PPOGATT)──────────▶ Pebble Watch
```

## What's displayed

### On the Rokid glasses (TCP :8090)

A rolling multi-source summary is pushed every 5 seconds:

```json
{"type":"summary","text":"Weather: 72°F WSW 8 mph  |  Snapmaker: Benchy 45%","sources":2}
{"type":"alert","text":"✅ Print complete: Benchy"}
```

### On the Pebble watch (BLE)

The watch shows one source at a time. Use the hardware buttons to cycle between sources:

```
┌─────────────────────┐
│ Weather        10:42│
├─────────────────────┤
│ 72°F WSW           │
│ 8 mph               │
│                     │
│ UV 2.3  Dry         │
│ Hum 58%             │
└─────────────────────┘
```

**Watch buttons:**
| Button | Action |
|--------|--------|
| ⬆ Up | Previous source |
| ● Select | Reserved |
| ⬇ Down | Next source |

## BLE Protocol (PPOGATT)

Implements the full **PPOGATT** (Pebble Protocol over GATT) stack used by Gadgetbridge and the official Pebble companion apps.

| Role | Description |
|------|-------------|
| Phone as GATT Server | Advertises `10000000-328E-0FBB-C642-1AA6699BDADA`; watch connects here and writes data |
| Phone as GATT Central | Scans for watch service `FED9`; subscribes to PPOGATT notify char `30000004-…` |
| Pebble Protocol | `[length:2BE][endpoint:2BE][payload]` framed inside PPOGATT packets |
| App Messages | Endpoint 48, 4 string keys (sourceName, line1, line2, line3) + button events |
| Phone Version | Endpoint 17 handshake, declares as iOS client |

## Watchapp

The `watchapp/` directory contains the PebbleOS C watchapp source.

### Building the watchapp

1. Create a project at [CloudPebble](https://cloudpebble.net) (or use the Pebble SDK locally).
2. Upload `src/main.c` as a new C file.
3. Set `appinfo.json` values (UUID **must** stay `a7e23b4c-5d1f-4a3e-8c6b-9f2e1d0b4a5c`).
4. Compile and install `.pbw` onto your watch.

The UUID in `appinfo.json` matches `watchappUUID` in `SourceModels.swift` — both must be identical.

## Data sources

| Source | Protocol | Interval |
|--------|----------|----------|
| Tempest weather | UDP :50222 broadcast | 3 s (rapid wind) / 1 min (full obs) |
| Snapmaker U1 | HTTP :8080 poll | 8 s |

Add more sources by creating a new `@MainActor class` with an `@Published var data: SourceData` and registering it in `HubViewModel.activeSources`.

## SDK Setup

The glasses now connect over **Bluetooth via the Rokid AI glasses SDK** — no Wi-Fi port or TCP server needed.

The only thing left for each app is filling in the three credential constants (`kAppKey`, `kAppSecret`, `kAccessKey`) from [account.rokid.com/#/setting/prove](https://account.rokid.com/#/setting/prove), then running `pod install`.

1. **Get credentials** at <https://account.rokid.com/#/setting/prove> and paste them into the glasses Swift file:
   ```swift
   private let kAppKey    = "YOUR_APP_KEY"
   private let kAppSecret = "YOUR_APP_SECRET"
   private let kAccessKey = "YOUR_ACCESS_KEY"
   ```

2. **Install CocoaPods dependencies** from the repo root:
   ```bash
   pod install
   open *.xcworkspace   # always open the .xcworkspace, not .xcodeproj
   ```

3. *(Glasses now connect automatically over Bluetooth — no TCP port needed.)*

## Setup

1. Open `RokidPebble.xcworkspace` in Xcode 15+ (after running `pod install`) 15+.
2. Set your team in Signing & Capabilities.
3. Build and run on iPhone (iOS 17+).
4. Grant Bluetooth and local network permissions when prompted.
5. In **Settings**: enable Tempest and/or Snapmaker, enter Snapmaker IP if needed.
6. Pair your Pebble watch via the Pebble Core companion app first; then the hub connects automatically via BLE.
7. Install the `watchapp` on your Pebble (see above).
8. *(Glasses now connect automatically over Bluetooth — no TCP port needed.)*

## Requirements

- iOS 17.0+
- Xcode 15+
- Pebble watch running PebbleOS (Core 2 Duo, Core Time 2, or older Pebble 2/Time)
- Pebble Core companion app installed (for initial BLE pairing)
- WeatherFlow Tempest hub and/or Snapmaker U1 on the same Wi-Fi (optional)
