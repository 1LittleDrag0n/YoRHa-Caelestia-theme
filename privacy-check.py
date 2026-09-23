#!/usr/bin/env python3
"""Scan this repo for anything personal before it goes public.

It looks for two kinds of thing:

  * generic secrets and identifiers - API keys, tokens, private keys, email
    addresses, IP and MAC addresses, phone numbers, coordinates;
  * *your* identity - the name, email, username, hostname and home path taken
    from this machine (git config, /etc/passwd, hostname), so a real name or
    location that no generic pattern would catch still gets flagged.

    ./privacy-check.py          scan and report
    ./privacy-check.py --fix    also rewrite /home/<you> paths to $HOME

Exit status is 1 when something was found, so it can gate a commit.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".cache"}
SKIP_SUFFIX = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".mp4", ".zip", ".tar",
               ".gz", ".so", ".o", ".ttf", ".otf", ".woff", ".woff2", ".ico", ".pdf"}

# ------------------------------------------------------------------ patterns
PATTERNS = [
    ("private key",     re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("GitHub token",    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{16,}")),
    ("OpenAI-style key", re.compile(r"\bsk-[A-Za-z0-9_\-]{20,}")),
    ("Google API key",  re.compile(r"\bAIza[0-9A-Za-z_\-]{30,}")),
    ("Slack token",     re.compile(r"\bxox[abprs]-[A-Za-z0-9\-]{10,}")),
    ("AWS key id",      re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("bearer token",    re.compile(r"(?i)\b(authorization|bearer)\b\s*[:=]\s*\S{12,}")),
    ("password/secret", re.compile(r"(?i)\b(password|passwd|secret|api[_-]?key|token)\b\s*[:=]\s*['\"]?\S{6,}")),
    ("email address",   re.compile(r"\b[\w.+-]+@[\w-]+\.[\w.]{2,}\b")),
    ("public IP",       re.compile(r"\b(?!10\.|127\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|0\.)"
                                   r"(\d{1,3}\.){3}\d{1,3}\b")),
    ("MAC address",     re.compile(r"\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b")),
    ("phone number",    re.compile(r"(?<![\w.])\+\d{1,3}[\s\-]?\d[\d\s\-]{7,}\d(?![\w.])")),
    ("coordinates",     re.compile(r"(?i)\b(lat(itude)?|lon(gitude)?)\b\s*[:=]\s*-?\d{1,3}\.\d{3,}")),
    ("wifi/psk",        re.compile(r"(?i)\b(psk|wpa|ssid)\b\s*[:=]\s*\S+")),
]

# Weather and location settings people forget about
LOCATION_HINTS = re.compile(r"(?i)\b(city|location|timezone|weather|postal|zip[_ ]?code|address)\b\s*[:=]\s*['\"]?[A-Za-z0-9/ ,._-]{2,}")


def identity_needles():
    """Strings that identify the person running this, taken from the machine."""
    out = {}

    def add(label, value):
        value = (value or "").strip()
        if len(value) >= 3 and value.lower() not in {"user", "root", "none", "localhost"}:
            out.setdefault(value, label)

    for key, label in (("user.name", "your git name"), ("user.email", "your git email")):
        try:
            add(label, subprocess.run(["git", "config", "--get", key],
                                      capture_output=True, text=True, timeout=5).stdout)
        except Exception:
            pass

    user = os.environ.get("USER") or os.environ.get("LOGNAME") or ""
    add("your username", user)
    add("your home path", os.path.expanduser("~"))

    try:
        add("your hostname", subprocess.run(["hostname"], capture_output=True, text=True, timeout=5).stdout)
    except Exception:
        pass

    # real name from /etc/passwd (GECOS), which is where "Full Name" lives
    try:
        import pwd
        gecos = pwd.getpwnam(user).pw_gecos.split(",")[0] if user else ""
        for part in gecos.replace(".", " ").split():
            add("your real name", part)
    except Exception:
        pass

    return out


def files():
    for path in sorted(REPO.rglob("*")):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.suffix.lower() in SKIP_SUFFIX:
            continue
        if path.name == Path(__file__).name:
            continue
        yield path


def redact(text, start, end):
    line = text.strip()
    if len(line) > 160:
        line = line[:160] + "…"
    return line


def main():
    fix = "--fix" in sys.argv
    needles = identity_needles()
    home = os.path.expanduser("~")
    findings = []

    for path in files():
        try:
            content = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue

        rel = path.relative_to(REPO)

        for lineno, line in enumerate(content.splitlines(), 1):
            for label, rx in PATTERNS:
                m = rx.search(line)
                if m:
                    findings.append((str(rel), lineno, label, redact(line, *m.span())))

            m = LOCATION_HINTS.search(line)
            if m:
                findings.append((str(rel), lineno, "possible location/weather setting", redact(line, *m.span())))

            for needle, label in needles.items():
                if needle in line:
                    findings.append((str(rel), lineno, label, redact(line, 0, 0)))

        if fix and home in content and home != "/root":
            path.write_text(content.replace(home, "$HOME"), encoding="utf-8")
            print(f"fixed: {rel} - replaced {home} with $HOME")

    if not findings:
        print("privacy check: nothing found. Safe to publish.")
        return 0

    print(f"privacy check: {len(findings)} thing(s) to look at\n")
    width = max(len(f"{f}:{l}") for f, l, _, _ in findings)
    for f, l, label, line in findings:
        print(f"  {f}:{l}".ljust(width + 4) + f"  [{label}]")
        print(f"      {line}\n")

    print("Not all of these are secrets - a home path or your username is usually")
    print("harmless, an email, hostname, real name, token or your city usually isn't.")
    print("Run with --fix to turn your home path into $HOME; edit the rest by hand.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
