#!/usr/bin/env python3
"""Inject the app's explicitly prepared Debug notification check; never contacts APNs/FCM."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

BUNDLE = "MANKumara.BreathRoute"


def simctl(*args):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", help="Target booted simulator UUID. Required if several are booted.")
    args = parser.parse_args()
    devices = [d for group in json.loads(simctl("list", "devices", "booted", "--json"))["devices"].values()
               for d in group if d.get("state") == "Booted"]
    if args.device:
        matches = [d for d in devices if d["udid"].lower() == args.device.lower()]
    else:
        matches = devices if len(devices) == 1 else []
    if len(matches) != 1:
        raise ValueError("Choose one booted simulator using --device UUID.")
    device = matches[0]
    container = Path(simctl("get_app_container", device["udid"], BUNDLE, "data"))
    fixture = container / "Documents" / "notification-check.apns"
    if not fixture.is_file():
        raise ValueError("In BreatheRoute, open You → Notifications → Check notifications → Prepare simulator push first.")
    payload = json.loads(fixture.read_text())
    if (payload.get("Simulator Target Bundle") != BUNDLE or payload.get("freeSource") != "simulator"
            or payload.get("freeKind") != "simulator_test" or payload.get("freeVersion") != "1"
            or not isinstance(payload.get("checkExpiresAt"), (int, float))
            or not time.time() < payload["checkExpiresAt"] <= time.time() + 901):
        raise ValueError("The simulator check has expired or is invalid. Prepare a fresh check in the app.")
    simctl("push", device["udid"], BUNDLE, str(fixture))
    print(f"Simulated notification injected into {device['name']}. Verify the banner and tap action.")
    print("This tests Simulator delivery only. No internet, FCM or APNs delivery was used.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, KeyError, json.JSONDecodeError) as error:
        # Do not print the fixture or any user-specific routing fields.
        print(str(error) if isinstance(error, ValueError) else "Simulator check could not run. Check the booted simulator and app installation.", file=sys.stderr)
        sys.exit(1)
