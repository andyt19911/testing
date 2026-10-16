#!/usr/bin/env python3
"""Generates assets/profiles/*.json.

The two demo profiles (CAN/UDS and K-line/KWP2000) describe the simulated
bike in lib/core/sim/virtual_bike.dart and are generated from one definition
so they can't drift apart. The generic BMW profiles carry only standard,
protocol-level identifiers; everything BMW-specific is marked unverified
until confirmed on a real bike with the Discovery console.

Run from the project root:  python3 tool/gen_profiles.py
"""
import copy
import json
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "profiles")


def h(v, w=4):
    return "0x%0*X" % (w, v)


IDENT = [
    ("vin", "VIN", 0xF190, 0x90),
    ("part", "Part number", 0xF187, 0x87),
    ("sw", "Software", 0xF189, 0x89),
    ("serial", "Serial number", 0xF18C, 0x8C),
]

SEC = {"level": 1, "algorithm": "sim-xor"}


def live(id, name, ident, unit, enc, group, basic=False, mn=None, mx=None):
    d = {"id": id, "name": name, "ident": ident, "unit": unit, "encoding": enc, "group": group}
    if basic:
        d["basic"] = True
    if mn is not None:
        d["min"] = mn
    if mx is not None:
        d["max"] = mx
    return d


PCT = 100 / 255

SIM_ECUS = [
    {
        "id": "engine", "name": "Engine control (BMS-X)", "shortName": "BMS-X", "address": 0x12,
        "category": "engine", "security": SEC,
        "liveData": [
            live("rpm", "Engine speed", 0x4001, "rpm", {"length": 2}, "Engine", True, 0, 9000),
            live("coolant", "Coolant temperature", 0x4002, "°C", {"offset": -40}, "Engine", True, -20, 120),
            live("throttle", "Throttle position", 0x4003, "%", {"scale": PCT}, "Engine", True, 0, 100),
            live("battery", "Battery voltage", 0x4005, "V", {"length": 2, "scale": 0.001, "decimals": 2}, "Electrical", True, 10, 16),
            live("iat", "Intake air temperature", 0x4004, "°C", {"offset": -40}, "Engine", False, -20, 80),
            live("gear", "Gear", 0x4006, "", {"type": "enum", "labels": {"0": "N", "1": "1", "2": "2", "3": "3", "4": "4", "5": "5", "6": "6"}}, "Engine"),
            live("lambda", "Lambda", 0x4007, "λ", {"length": 2, "scale": 0.0001, "decimals": 3}, "Engine", False, 0.7, 1.3),
            live("oil", "Oil temperature", 0x4008, "°C", {"offset": -40}, "Engine", False, -20, 150),
        ],
        "dtcText": {"2A9400": "Intake air temperature sensor: implausible signal"},
        "procedures": [
            {
                "id": "throttle_adapt", "name": "Reset throttle adaptation", "kind": "adaptation",
                "description": "Clears the learned throttle-valve values, e.g. after cleaning or replacing the throttle body.",
                "steps": [{"op": "security"}, {"op": "routine", "ident": 0xA001, "label": "Resetting adaptation values"}],
                "successMessage": "Switch the ignition off for 10 seconds, then start the engine and let it idle for 3 minutes without touching the throttle.",
            },
            {
                "id": "gear_teach", "name": "Teach-in gear position sensor", "kind": "calibration",
                "description": "Teaches the neutral position after the gear sensor was replaced or adjusted.",
                "preconditions": {"extra": ["Gearbox is in neutral"]},
                "steps": [
                    {"op": "security"},
                    {"op": "prompt", "message": "Put the gearbox in neutral, then tap Continue."},
                    {"op": "routine", "ident": 0xA002, "label": "Learning neutral position"},
                ],
            },
        ],
    },
    {
        "id": "abs", "name": "ABS (Integral ABS)", "shortName": "ABS", "address": 0x29,
        "category": "abs", "security": SEC,
        "liveData": [
            live("v_front", "Front wheel speed", 0x4101, "km/h", {"length": 2, "scale": 0.1, "decimals": 1}, "Brakes", False, 0, 250),
            live("v_rear", "Rear wheel speed", 0x4102, "km/h", {"length": 2, "scale": 0.1, "decimals": 1}, "Brakes", False, 0, 250),
            live("pressure", "Brake pressure", 0x4103, "bar", {}, "Brakes", False, 0, 200),
        ],
        "dtcText": {"5E2101": "Front wheel speed sensor: no signal"},
        "procedures": [
            {
                "id": "bleed_front", "name": "Bleed front brake circuit", "kind": "bleed",
                "description": "Cycles the ABS pressure modulator so trapped air leaves the front circuit.",
                "preconditions": {"extra": ["Bike is on its centre stand", "Bleeding bottle is connected to the front calipers"]},
                "steps": [
                    {"op": "security"},
                    {"op": "prompt", "message": "Open the front caliper bleed screws and keep the reservoir topped up."},
                    {"op": "routine", "ident": 0xB001, "label": "Cycling front modulator"},
                    {"op": "prompt", "message": "Pull and hold the front brake lever, then tap Continue."},
                    {"op": "routine", "ident": 0xB001, "label": "Cycling front modulator (2)"},
                    {"op": "prompt", "message": "Close the bleed screws and top up the reservoir to MAX."},
                ],
                "successMessage": "Check the lever is firm before you ride.",
            },
            {
                "id": "bleed_rear", "name": "Bleed rear brake circuit", "kind": "bleed",
                "description": "Cycles the ABS pressure modulator so trapped air leaves the rear circuit.",
                "preconditions": {"extra": ["Bike is on its centre stand", "Bleeding bottle is connected to the rear caliper"]},
                "steps": [
                    {"op": "security"},
                    {"op": "prompt", "message": "Open the rear caliper bleed screw and keep the reservoir topped up."},
                    {"op": "routine", "ident": 0xB002, "label": "Cycling rear modulator"},
                    {"op": "prompt", "message": "Press and hold the rear brake pedal, then tap Continue."},
                    {"op": "routine", "ident": 0xB002, "label": "Cycling rear modulator (2)"},
                    {"op": "prompt", "message": "Close the bleed screw and top up the reservoir."},
                ],
                "successMessage": "Check the pedal is firm before you ride.",
            },
            {
                "id": "pump_test", "name": "ABS pump motor test", "kind": "actuator",
                "description": "Runs the ABS pump for two seconds. You should hear it.",
                "steps": [
                    {"op": "session"},
                    {"op": "io", "ident": 0xB010, "param": 3, "data": "01", "label": "Pump on"},
                    {"op": "wait", "ms": 2000, "label": "Pump running"},
                    {"op": "io", "ident": 0xB010, "param": 0, "label": "Pump off"},
                ],
            },
        ],
    },
    {
        "id": "zfe", "name": "Central electronics (ZFE)", "shortName": "ZFE", "address": 0x40,
        "category": "body", "security": SEC,
        "liveData": [
            live("fuel", "Fuel level", 0x4201, "%", {"scale": PCT}, "Body", False, 0, 100),
        ],
        "coding": [{
            "id": "zfe_main", "name": "Equipment", "ident": 0x3100, "length": 6,
            "params": [
                {"id": "tpms", "name": "Tyre pressure monitoring (RDC)", "byte": 0, "mask": "0x01",
                 "description": "Switch off if the TPMS sensors were removed, so the warning light stays off. The instrument cluster is changed with it.",
                 "options": [{"value": 0, "label": "Not fitted"}, {"value": 1, "label": "Fitted"}],
                 "linked": [{"ecu": "kombi", "param": "tpms_display", "map": {"0": 0, "1": 1}}]},
                {"id": "heated_grips", "name": "Heated grips", "byte": 1, "mask": "0x01",
                 "description": "Tell the bike heated grips are fitted.",
                 "options": [{"value": 0, "label": "Not fitted"}, {"value": 1, "label": "Fitted"}]},
                {"id": "cruise", "name": "Cruise control", "byte": 1, "mask": "0x02",
                 "description": "Only switch on if the cruise control switch unit is fitted.",
                 "options": [{"value": 0, "label": "Not fitted"}, {"value": 2, "label": "Fitted"}], "risk": "medium"},
                {"id": "aux_lights", "name": "Auxiliary lights", "byte": 2, "mask": "0x03",
                 "description": "Type of auxiliary lights connected to the ZFE.",
                 "options": [{"value": 0, "label": "Not fitted"}, {"value": 1, "label": "LED auxiliary lights"}, {"value": 2, "label": "Halogen fog lights"}],
                 "risk": "medium", "warning": "The wrong type can trigger a bulb fault warning."},
                {"id": "welcome_light", "name": "Welcome light", "byte": 3, "mask": "0x01",
                 "description": "Low beam comes on briefly when you unlock the bike.",
                 "options": [{"value": 0, "label": "Off"}, {"value": 1, "label": "On"}]},
            ],
        }],
        "procedures": [
            {
                "id": "fuel_cal", "name": "Calibrate fuel level sensor", "kind": "calibration",
                "description": "Re-learns the full-tank reading after the fuel sensor was replaced.",
                "steps": [
                    {"op": "security"},
                    {"op": "prompt", "message": "Fill the tank to the brim, then tap Continue."},
                    {"op": "routine", "ident": 0xC001, "label": "Learning full tank"},
                ],
            },
            {
                "id": "esa_cal", "name": "Calibrate ESA ride height", "kind": "calibration",
                "description": "Sets the reference ride height of the electronic suspension.",
                "preconditions": {"extra": ["Bike is upright on level ground", "No rider or luggage"]},
                "steps": [{"op": "security"}, {"op": "routine", "ident": 0xC002, "label": "Measuring ride height"}],
            },
        ],
    },
    {
        "id": "kombi", "name": "Instrument cluster (KOMBI)", "shortName": "KOMBI", "address": 0x60,
        "category": "cluster", "security": SEC,
        "liveData": [
            live("odo", "Odometer", 0x4310, "km", {"length": 3}, "Service"),
            live("service_km", "Service due in", 0x5002, "km", {"length": 3}, "Service"),
        ],
        "coding": [{
            "id": "kombi_main", "name": "Display", "ident": 0x3000, "length": 8,
            "params": [
                {"id": "units", "name": "Distance unit", "byte": 0, "mask": "0x01",
                 "options": [{"value": 0, "label": "Kilometres"}, {"value": 1, "label": "Miles"}]},
                {"id": "clock", "name": "Clock format", "byte": 0, "mask": "0x02",
                 "options": [{"value": 0, "label": "24-hour"}, {"value": 2, "label": "12-hour"}]},
                {"id": "temp_unit", "name": "Temperature unit", "byte": 0, "mask": "0x04",
                 "options": [{"value": 0, "label": "°C"}, {"value": 4, "label": "°F"}]},
                {"id": "tpms_display", "name": "Tyre pressure display", "byte": 1, "mask": "0x01",
                 "description": "Shows tyre pressures in the cluster. Changed together with TPMS in the ZFE.",
                 "options": [{"value": 0, "label": "Off"}, {"value": 1, "label": "On"}]},
                {"id": "drl", "name": "Daytime running light", "byte": 1, "mask": "0x06",
                 "description": "How the daytime running light behaves.",
                 "options": [{"value": 0, "label": "Off"}, {"value": 2, "label": "Automatic"}, {"value": 4, "label": "Always on"}],
                 "warning": "Check your local road rules before turning it off."},
                {"id": "shift_light", "name": "Shift light", "byte": 2, "mask": "0x0F",
                 "options": [{"value": 0, "label": "Off"}, {"value": 7, "label": "7 000 rpm"}, {"value": 8, "label": "8 000 rpm"}, {"value": 9, "label": "9 000 rpm"}]},
                {"id": "service_display", "name": "Service reminder in display", "byte": 3, "mask": "0x01",
                 "description": "Hides the service reminder. It doesn't change the service interval.",
                 "options": [{"value": 0, "label": "Shown"}, {"value": 1, "label": "Hidden"}], "risk": "medium"},
            ],
        }],
        "procedures": [
            {
                "id": "service_reset", "name": "Reset service reminder", "kind": "service",
                "description": "Sets the next service date and distance after a service.",
                "needsLongMessages": True,
                "inputs": [
                    {"id": "distance", "label": "Next service in", "default": 10000, "min": 1000, "max": 30000, "step": 1000, "unit": "km"},
                    {"id": "months", "label": "or after", "default": 12, "min": 1, "max": 24, "step": 1, "unit": "months"},
                ],
                "status": [
                    {"id": "due_date", "name": "Service due on", "ident": 0x5001, "encoding": {"type": "date", "length": 4}},
                    {"id": "due_km", "name": "Service due in", "ident": 0x5002, "encoding": {"length": 3}, "unit": "km"},
                ],
                "steps": [
                    {"op": "security"},
                    {"op": "write", "ident": 0x5001, "data": "{due.dd|bcd8}{due.mm|bcd8}{due.yyyy|bcd16}", "label": "Writing next service date"},
                    {"op": "write", "ident": 0x5002, "data": "{input.distance|u24}", "label": "Writing next service distance"},
                    {"op": "routine", "ident": 0x5100, "label": "Confirming service"},
                    {"op": "verify", "ident": 0x5001, "data": "{due.dd|bcd8}{due.mm|bcd8}{due.yyyy|bcd16}"},
                ],
                "successMessage": "The service reminder was reset.",
            },
            {
                "id": "set_date", "name": "Set cluster date and time", "kind": "date",
                "description": "Copies the phone's date and time to the instrument cluster. The service reset needs a correct date.",
                "needsLongMessages": True,
                "status": [{"id": "date", "name": "Cluster date", "ident": 0x5003, "encoding": {"type": "date", "length": 6}}],
                "steps": [
                    {"op": "security"},
                    {"op": "write", "ident": 0x5003, "data": "{today.dd|bcd8}{today.mm|bcd8}{today.yyyy|bcd16}{today.HH|bcd8}{today.MI|bcd8}", "label": "Writing date and time"},
                ],
            },
        ],
    },
]

# Standard SAE J1979 mode 01 PIDs (real, not BMW-specific).
OBD_LIVE = [
    live("rpm", "Engine speed", 0x0C, "rpm", {"length": 2, "scale": 0.25}, "OBD-II", True, 0, 9000),
    live("coolant", "Coolant temperature", 0x05, "°C", {"offset": -40}, "OBD-II", True, -20, 120),
    live("throttle", "Throttle position", 0x11, "%", {"scale": PCT}, "OBD-II", True, 0, 100),
    live("battery", "Control module voltage", 0x42, "V", {"length": 2, "scale": 0.001, "decimals": 2}, "OBD-II", True, 10, 16),
    live("speed", "Vehicle speed", 0x0D, "km/h", {}, "OBD-II", False, 0, 250),
    live("load", "Engine load", 0x04, "%", {"scale": PCT}, "OBD-II", False, 0, 100),
    live("map", "Intake pressure", 0x0B, "kPa", {}, "OBD-II", False, 0, 255),
    live("iat", "Intake air temperature", 0x0F, "°C", {"offset": -40}, "OBD-II", False, -20, 80),
    live("timing", "Ignition advance", 0x0E, "°", {"scale": 0.5, "offset": -64, "decimals": 1}, "OBD-II", False, -10, 50),
    live("runtime", "Time since start", 0x1F, "s", {"length": 2}, "OBD-II"),
    live("fuel", "Fuel level", 0x2F, "%", {"scale": PCT}, "OBD-II", False, 0, 100),
    live("ambient", "Ambient temperature", 0x46, "°C", {"offset": -40}, "OBD-II", False, -20, 50),
    live("oil", "Oil temperature", 0x5C, "°C", {"offset": -40}, "OBD-II", False, -20, 150),
]


def ident_list(kwp):
    return [{"id": i, "name": n, "ident": h(k if kwp else u, 2 if kwp else 4)} for i, n, u, k in IDENT]


def finalize(ecu, kwp, verified):
    e = copy.deepcopy(ecu)
    e["protocol"] = "kwp" if kwp else "uds"
    e["address"] = h(e["address"], 2)
    e["verified"] = verified
    e["identification"] = ident_list(kwp)

    def m(v):
        return h(v & 0xFF, 2) if kwp else h(v)

    for v in e.get("liveData", []):
        v["ident"] = m(v["ident"])
    for b in e.get("coding", []):
        b["ident"] = m(b["ident"])
    for p in e.get("procedures", []):
        p["verified"] = verified
        for s in p.get("steps", []):
            if "ident" in s:
                s["ident"] = m(s["ident"])
        for s in p.get("status", []):
            s["ident"] = m(s["ident"])
    if kwp:
        e["dtcText"] = {k[:4]: v for k, v in e.get("dtcText", {}).items()}
        e["writeSession"] = "0x86"
        if "security" in e:
            e["security"] = dict(e["security"], session="0x86")
    return e


def obd_ecu(verified=True):
    return {
        "id": "obd", "name": "Engine (OBD-II standard data)", "shortName": "OBD", "address": "0x7DF",
        "protocol": "obd", "category": "obd", "verified": verified, "liveData": copy.deepcopy(OBD_LIVE),
    }


def write(name, profile):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
        json.dump(profile, f, indent=2, ensure_ascii=False)
        f.write("\n")


write("sim_can.json", {
    "id": "sim-can", "name": "Demo bike — CAN (UDS)", "bus": "can", "simulator": True,
    "years": "Simulator", "models": ["DEMO"],
    "notes": "Simulated bike with every feature. Nothing is sent to a real motorcycle.",
    "ecus": [finalize(e, False, True) for e in SIM_ECUS] + [obd_ecu()],
})

write("sim_kline.json", {
    "id": "sim-kline", "name": "Demo bike — K-line (KWP2000)", "bus": "kline", "simulator": True,
    "years": "Simulator", "models": ["DEMO"],
    "notes": "Simulated older bike on K-line.",
    "ecus": [finalize(e, True, True) for e in SIM_ECUS],
})


def generic(id, name, short, addr, cat, kwp):
    return {
        "id": id, "name": name, "shortName": short, "address": h(addr, 2),
        "protocol": "kwp" if kwp else "uds", "category": cat, "verified": False,
        "identification": ident_list(kwp),
    }


GEN_NOTE = ("Starting point only. The control-unit addresses follow BMW's usual conventions "
            "and are not yet confirmed on this model: run Discovery › Find control units on your bike, "
            "then add what it finds. Writing is disabled until a profile is verified.")

write("bmw_can.json", {
    "id": "bmw-can", "name": "BMW, CAN-bus models (about 2013 on)", "bus": "can",
    "years": "2013–",
    "models": ["R 1200 / 1250 LC", "S 1000 RR/R/XR (2015 on)", "K 1600", "F 750/850/900", "R nineT", "R 18", "M 1000"],
    "notes": GEN_NOTE,
    "ecus": [
        obd_ecu(),
        generic("engine", "Engine control", "DME", 0x12, "engine", False),
        generic("abs", "ABS", "ABS", 0x29, "abs", False),
        generic("kombi", "Instrument cluster", "KOMBI", 0x60, "cluster", False),
    ],
})

write("bmw_kline.json", {
    "id": "bmw-kline", "name": "BMW, K-line models (about 2004–2016)", "bus": "kline",
    "years": "2004–2016",
    "models": ["R 1200 GS/RT/R/S (air/oil-cooled)", "K 1200 / K 1300", "F 650/700/800", "G 650", "S 1000 RR (to 2014)", "HP2"],
    "notes": GEN_NOTE,
    "ecus": [
        generic("engine", "Engine control (BMS-K)", "BMS-K", 0x12, "engine", True),
        generic("abs", "ABS", "ABS", 0x29, "abs", True),
        generic("kombi", "Instrument cluster", "KOMBI", 0x60, "cluster", True),
    ],
})
print("profiles written to", os.path.normpath(OUT))
