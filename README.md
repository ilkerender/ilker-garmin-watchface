# Tactical Grid — Garmin Venu 3S Watch Face

Hey, my name is Ilker and this is my watch face. I've always loved uncluttered watch faces that just give me the right data — nothing more, nothing less. Feel free to customize it and make it your own.

---

A minimalist, AMOLED-optimised watch face for the **Garmin Venu 3S** built with the Connect IQ SDK. Pure black background, white data, surgical layout — everything you need at a glance, nothing you don't.

## Install on your watch (no coding required)

You need a **Garmin Venu 3S**. No computer tools, no accounts — just a USB cable.

**Step 1 — Download the file**

Download [`venu3swatchface.prg`](venu3swatchface.prg) from this page.
(Click the filename → click the download button in the top-right corner of the file preview.)

**Step 2 — Connect your watch**

Plug your Venu 3S into your computer with its USB charging cable. Your watch will appear as a drive — like a USB stick — in Finder (Mac) or File Explorer (Windows).

**Step 3 — Copy the file**

Open the watch drive and navigate to:
```
GARMIN → Apps
```
Drag `venu3swatchface.prg` into that folder.

**Step 4 — Eject and select**

Safely eject the watch, then on the watch go to:
**Settings → Watch Face** (or long-press the current watch face) and pick **Tactical Grid**.

That's it.

---

## Screenshots

| Simulator | On the Wrist |
|:---------:|:------------:|
| ![Simulator](WATCH1.png) | ![On wrist](WATCH2.png) |

## Features

### Health dot row (top)
Seven dots — one per day, today on the right — give you a week-at-a-glance health summary without numbers.

- **Top half** — Resting heart rate colour: green `< 57 bpm` · yellow `57–59` · red `≥ 60`
- **Bottom half** — Green when the day's step goal was met, or ≥ 5 vigorous / ≥ 20 moderate active minutes logged

> **Two things to know about the RHR dot colours:**
> - **Fills in over time.** The watch records each day's RHR locally as you wear it. Past dots have no colour on a fresh install and gain colour going forward — expect a full week of colour after about seven days of wear.
> - **Approximation.** The value used is Garmin's `averageRestingHeartRate` (a rolling average), not the exact per-night RHR shown in the Garmin app. It's close, but not identical.

### Top metrics
| Left | Centre | Right |
|------|--------|-------|
| STP — steps | DIST — distance (km or mi) | BODY — body battery (0–100) |

Slim fading vertical dividers separate each column.

### Time band (centre)
Large time display (`FONT_NUMBER_THAI_HOT`) with a stacked date block (weekday + day of month) aligned to the right. Font size is auto-selected so the full layout always fits inside the round bezel.

### Bottom metrics
| Left | Centre | Right |
|------|--------|-------|
| Sleep score (or HRV stress fallback) + moon icon | HR — current heart rate | Battery % + icon |

### Always-On Display (AOD)
Dimmed time + date only, with per-minute pixel shift for burn-in protection.

## Design principles

- **Pure black background** — AMOLED pixel-off efficiency
- **Circle-aware layout** — chord formula ensures no element clips the round bezel
- **Graceful fallbacks** — every metric degrades to `--` rather than crashing
- **Strict type safety** — compiled with `monkeyC.typeCheckLevel: Strict`

## Requirements

| Item | Version |
|------|---------|
| Target device | Garmin Venu 3S |
| Connect IQ SDK | 9.2.0+ |
| Min API level | 4.0.0 |

### Permissions used
- `SensorHistory` — body battery, HRV/stress
- `ComplicationSubscriber` — sleep score
- `UserProfile` — resting heart rate for dot colours

## Building

1. Install the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) and set `SDK` in `run.sh` to your SDK path.
2. Generate a developer key:
   ```
   openssl genrsa -out developer_key 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key -out developer_key -nocrypt
   ```
3. Build and launch the simulator:
   ```
   bash run.sh
   ```
4. To sideload directly, copy `bin/venu3swatchface.prg` to `GARMIN/Apps/` on the watch.

## Project structure

```
├── manifest.xml              # App manifest (permissions, target device)
├── monkey.jungle             # Build descriptor
├── run.sh                    # Build + simulator launch script
├── source/
│   ├── WatchFaceApp.mc       # App entry point
│   └── WatchFaceView.mc      # All rendering logic
└── resources/
    ├── drawables/            # Launcher icon + drawables.xml
    └── strings/              # App name string
```

## License

MIT — do whatever you want with it, attribution appreciated.
