# RideScope — analysis of MotoScan and the build plan

## 1. What MotoScan does (from public sources)

MotoScan (`de.wgsoft.motoscan`, Android only) is a BMW motorcycle diagnostic app
that talks to the bike through an OBD adapter (OBDLink LX/MX/MX+, UniCarScan
UCSI-2000/2100, or ELM327 "with restrictions"). From the Play Store listing,
changelogs and owner forums, its features are:

| Area | MotoScan feature |
|---|---|
| Identification | Find the bike's control units (ECUs) and read their part number, hardware/software versions and VIN |
| Fault memory | Read and clear fault codes (DTCs); freeze frames (the "snapshot" data stored with a fault) |
| Live data | Real-time values (RPM, temperatures, throttle, battery, gear, lambda…) per ECU |
| Service | Reset the service reminder (date and distance), set the date in the instrument cluster |
| Coding | Change ECU settings, e.g. turn the TPMS (RDC) off/on in ZFE + KOMBI, DRL, menu options |
| Adaptations | Reset adaptations; throttle and gear-sensor teach-in (BMS-K/KP/KP2, BMS-X, BMS-MP, BMS-O); fuel-sensor calibration (ZFE BASIC/LOW); ESA calibration (ZFE HIGH) |
| Actuators | Actuator tests, including ABS brake bleeding on ABS2 K15 / Integral ABS2 K25 |
| Licensing | Free "Lite" version for checking compatibility (very limited data, most service functions locked) plus a paid licence; prices and tiers are shown in the app |

Known pain points from owner forums and the developer's own notes:

* Cheap ELM327 clones can't send long messages, so date setting and service
  reset fail on them, and the app doesn't explain why well.
* Android only. There is no iOS version.
* The UI is a dense, list-driven "engineering" layout: hard to read in sunlight
  and hard to use with gloves. Functions are scattered per ECU rather than per
  task ("reset my service").
* Coding is a raw list of values with little explanation, and there is no
  obvious backup/restore history.
* "Functions depend on the control unit and the app's development level", and
  you only find out what your bike supports by trying.

## 2. How to build it: clean-room, not a copy

The options were (a) decompile the MotoScan APK, (b) watch it in an emulator,
(c) build from scratch.

**We are building from scratch (clean-room).**

* **Decompiling the APK and reusing its code or data tables** would copy
  wgsoft's copyrighted work and break its licence terms. A commercial product
  built that way is a legal liability. The valuable part of MotoScan is its
  table of ECU addresses, identifiers and coding bits, and that is exactly what
  you can't take.
* **An emulator doesn't help.** An Android emulator has no Bluetooth link to a
  real adapter, so MotoScan in an emulator never gets past "connect". Watching
  it would only show screens, which the Play listing already shows.
* **The protocols themselves are open standards.** KWP2000 (ISO 14230),
  UDS (ISO 14229), ISO-TP (ISO 15765-2) and the ELM327/STN AT command sets are
  public. What is BMW-specific is which ECU sits at which address and which
  identifier holds which value. That can be learned legitimately **from your
  own bike** with the built-in Discovery tool (section 5).

## 3. Architecture

```
┌───────────────────────── Flutter UI (Android · iOS · desktop · web demo) ─────────────────────────┐
│ Garage · Connect wizard · Health check · Faults · Live data · Service · Coding · Adaptations ·      │
│ Actuators · Discovery console · Licence/paywall                                                     │
└──────────────┬──────────────────────────────────────────────────────────────────────────────────────┘
               │ DiagnosticSession (one per bike connection)
┌──────────────▼──────────────┐   ┌───────────────────────────┐   ┌──────────────────────────┐
│ Feature services             │   │ ECU profiles (JSON)        │   │ Licensing                 │
│ ServiceResetService          │◀──│ addresses, DIDs, scaling,  │   │ Free / Plus / Pro         │
│ CodingEngine (backup·diff·   │   │ coding bits, procedures,   │   │ signed licence tokens     │
│   write·verify·restore)      │   │ verified flag              │   │ (Ed25519) + store IAP     │
│ LiveDataService · DtcService │   └───────────────────────────┘   └──────────────────────────┘
└──────────────┬──────────────┘
┌──────────────▼──────────────┐
│ Protocol: DiagClient         │  Kwp2000Client (K-line)  ·  UdsClient (CAN, BMW extended addressing)
├─────────────────────────────┤
│ Adapter: Elm327Adapter       │  init, capability detection (ELM vs STN, long-message test,
│                              │  voltage), header/CAN-address switching, response parsing
├─────────────────────────────┤
│ Transport                    │  Bluetooth Classic SPP (Android) · BLE (Android/iOS) · Wi-Fi TCP ·
│                              │  Simulator (virtual bike, used for demo mode and tests)
└─────────────────────────────┘
```

Key choices:

* **Flutter** gives one codebase for Android *and* iOS (BLE adapters such as
  OBDLink CX/MX+ and Vgate iCar Pro BLE), something MotoScan doesn't have. The
  web build runs against the simulator for demos and screenshots.
* **Data-driven ECU profiles.** No ECU knowledge is hard-coded in Dart. Each
  profile is a JSON file, so support for a new bike is a data update, and
  each entry carries a `verified` flag. Unverified write operations are
  blocked unless the user switches on *Expert mode* (Pro tier).
* **A simulator built into the stack.** A virtual bike speaks real ELM327 AT
  commands, KWP2000 and UDS byte-for-byte. Every feature runs end-to-end in
  tests and in demo mode without a motorcycle.

## 4. Protocol notes (to be confirmed on the test bike)

| Bike generation | Connector | Physical | Protocol | ELM327 setup |
|---|---|---|---|---|
| ~2004–2016 (K25, K2x, K4x…) | Round 10-pin | K-line, 10 400 baud, fast init | KWP2000, header `80 <ecu> F1` | `ATSP5`, `ATSH 80 xx F1`, `ATFI` |
| Liquid-cooled and newer (K5x/K6x/K7x…; 2017+ rectangular 16-pin) | 10-pin or 16-pin | CAN 500 kbit/s | UDS over ISO-TP, BMW extended addressing: tester `0x6F1`, first data byte = ECU address; reply on `0x600+ecu` | `ATSP6`, `ATSH 6F1`, `ATCEA xx`, `ATCRA 6xx`, flow-control headers |

Adapter limits matter, and the app detects them on connect:

* A genuine ELM327 sends at most about 7 data bytes per K-line message and
  only single CAN frames. Writing the date or a coding block needs more, which
  is why cheap clones fail on service reset.
* STN-based adapters (OBDLink LX/MX+/CX) can send long messages with `STPX`.
  RideScope tests this on connect and tells the user before they start a
  procedure, not halfway through it.

The ECU addresses in `assets/profiles/*.json` are starting points marked
`"verified": false`. They must be confirmed with Discovery on the test bike
before any write is enabled for normal users.

## 5. Making the database real: Discovery

Pro tier includes a **Discovery** console that:

1. sweeps the K-line and CAN address ranges and lists every ECU that answers;
2. reads standard identification (KWP `1A xx`, UDS `22 F18x/F19x`);
3. scans the identifier range read-only (`21 xx` / `22 xxxx`) and records
   what answers, so you can watch values change (twist the throttle, switch
   on the DRL) and name them;
4. records full raw logs that can be exported and turned into a profile.

Discovery never writes. Every write that ends up in a profile has to be
confirmed by reading the value back after a change made on the bike itself, or
documented in the BMW-published repair information for that model.

## 6. Improvements over MotoScan

| MotoScan | RideScope |
|---|---|
| Android only | Android + iOS (BLE adapters) + desktop; web demo |
| Per-ECU menus | Task-first home screen: *Health check*, *Reset service*, *Read faults*, *Live data*, *Settings (coding)* |
| Clone adapters fail mid-procedure | Connection check grades the adapter (voltage, long messages, CAN/K-line) and greys out what it can't do, with the reason |
| Raw coding lists | Each option has a plain-language description, the current value, a preview of the change, an **automatic backup before every write**, read-back verification and one-tap restore from the backup history |
| Fault codes with terse text | Severity, plain-language explanation, "safe to ride?" hint, freeze frame, and a shareable health report |
| Live data as numbers | Gauges plus scrolling multi-channel charts, recording and CSV export |
| Little safety checking | Pre-flight checks before writes: battery voltage ≥ 12.2 V, engine off, ignition on, adapter capable, profile verified |
| Small touch targets | Large, glove-friendly targets; high-contrast dark theme readable in sunlight |

## 7. Licence tiers

| | **Free** | **Plus** | **Pro** |
|---|---|---|---|
| Find ECUs, identification, VIN | ✓ | ✓ | ✓ |
| Read faults | ✓ | ✓ | ✓ |
| Clear faults | – | ✓ | ✓ |
| Live data | Basic values (RPM, temperatures, throttle, battery) | All values, charts, recording, CSV | ✓ |
| Freeze frames, health report | – | ✓ | ✓ |
| Service reset, set cluster date | – | ✓ | ✓ |
| Coding (with backup/restore) | – | – | ✓ |
| Adaptation reset / teach-in, actuator tests, ABS bleed | – | – | ✓ |
| Discovery console, raw logs, expert mode | – | – | ✓ |
| Bikes (VINs) | 1 | 2 | Unlimited |

Entitlements come from either a store purchase (Google Play / App Store, needed
for in-app sales under store rules) or a signed licence token (Ed25519, checked
offline) for workshop and direct sales. The tier gate is enforced in the
service layer, not only by hiding buttons.

## 8. Deliberately out of scope

These are left out on purpose, for legal and safety reasons:

* Odometer changes.
* Immobilizer/EWS key programming and any security-access bypass. Seed/key
  algorithms are pluggable but not shipped.
* Emissions-related defeats (lambda/cat/EVAP/exhaust-flap deletes, ECU
  re-flashing).
* ECU firmware flashing. A failed flash can brick an ECU, and that risk is
  too high for a phone app.

## 9. Testing on the real bike (recommended order)

1. Demo mode first (simulator), to learn the flows.
2. Connection check with your adapter. Note what it reports for long messages and CAN/K-line.
3. Discovery address sweep → identification. Send the exported log so the
   profile addresses can be marked verified.
4. Read-only features: faults, live data, freeze frames.
5. Service reset (writes only the KOMBI service counters, which you can redo).
6. Coding, one low-risk option first (for example a menu/display option),
   with the automatic backup. Confirm restore works before trying anything
   else.
7. Adaptations and actuators last.
