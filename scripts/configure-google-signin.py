#!/usr/bin/env python3
"""Generate the ignored OAuth callback build setting without printing credentials."""
from pathlib import Path
import plistlib
import re
import sys


def callback_scheme(config):
    if config.get("BUNDLE_ID") != "MANKumara.BreathRoute":
        raise ValueError("The Firebase file does not match this app's bundle identifier.")
    client = config.get("CLIENT_ID", "")
    reverse = config.get("REVERSED_CLIENT_ID", "")
    if not client and not reverse:
        return None
    if not isinstance(client, str) or not re.fullmatch(r"[A-Za-z0-9-]+\.apps\.googleusercontent\.com", client):
        raise ValueError("The Google OAuth client ID is missing or malformed. Download a fresh Firebase plist.")
    if reverse != ".".join(reversed(client.split("."))):
        raise ValueError("The Google OAuth client and callback IDs do not match.")
    return reverse


def main():
    root = Path(__file__).resolve().parents[1]
    source = root / "BreathRoute" / "GoogleService-Info.plist"
    destination = root / "GoogleSignIn.local.xcconfig"
    try:
        with source.open("rb") as file:
            config = plistlib.load(file)
        scheme = callback_scheme(config)
    except FileNotFoundError:
        scheme = None
    except (ValueError, TypeError, plistlib.InvalidFileException) as error:
        print(f"Google sign-in configuration was not changed: {error}", file=sys.stderr)
        return 1
    # Rewrite even for a missing OAuth client so an old project's scheme cannot linger.
    value = scheme or "breatheroute-unconfigured"
    content = "// Generated locally; do not commit. Contains an OAuth callback ID, no API key.\n"
    content += f"GOOGLE_REVERSED_CLIENT_ID = {value}\n"
    temporary = destination.with_suffix(".tmp")
    temporary.write_text(content)
    temporary.replace(destination)
    print("Google callback configured. Rebuild the app." if scheme else
          "Google client fields are absent. Enable Google in Firebase and download a fresh plist; local features remain available.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
