#!/usr/bin/env bash
# room-calendar — the Google calendars Room shows (Home's "Next", standby, the assistant). Each is its "Secret address
# in iCal format" (Google Calendar → Settings → the calendar → Integrate calendar), kept in ~/.config/room/config.json.
#   room-calendar add      paste one in (it isn't shown on screen or kept in your shell history), then Room restarts
#   room-calendar list     which accounts are in (the secret part of each address stays hidden)
#   room-calendar clear    take them all out
# The addresses are secrets: anyone with one can read that calendar. They never go in the repo.
set -euo pipefail
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/room/config.json"
[ -f "$CFG" ] || { echo "No $CFG yet — set Room up first."; exit 1; }

edit() {   # python3 - <what> : reads $CFG, changes icalURLs, writes it back (same permissions)
  ROOM_CFG="$CFG" python3 - "$@" <<'PY'
import json, os, sys, tempfile
cfg_path = os.environ["ROOM_CFG"]
cfg = json.load(open(cfg_path))
old = cfg.get("icalURL")
urls = list(cfg.get("icalURLs") or []) + ([old] if isinstance(old, str) and old else list(old or []))
cfg.pop("icalURL", None)
what = sys.argv[1]
if what == "add":
    new = os.environ["ROOM_NEW_URL"]
    if new in urls:
        print("  That calendar is already in.")
    else:
        urls.append(new)
elif what == "clear":
    urls = []
def who(u):
    try:
        acct = u.split("/ical/")[1].split("/")[0].replace("%40", "@")
    except IndexError:
        acct = "a calendar"
    return acct + (" (public address)" if "/public/" in u else "")
if what == "list" or what == "add":
    print(f"  {len(urls)} calendar{'s' if len(urls) != 1 else ''} in Room:" if urls else "  No calendars in Room.")
    for u in urls:
        print("   ·", who(u))
cfg["icalURLs"] = urls
if what != "list":
    mode = os.stat(cfg_path).st_mode & 0o777
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(cfg_path))
    with os.fdopen(fd, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False); f.write("\n")
    os.chmod(tmp, mode)
    os.replace(tmp, cfg_path)
PY
}

restart() { systemctl --user restart room.service 2>/dev/null && echo "  ✓ Room restarted — the calendar shows within a minute." || echo "  Restart Room to see it."; }

case "${1:-}" in
  add)
    read -r -s -p "Paste the calendar's secret address in iCal format, then press Enter: " URL; echo
    URL="${URL//[[:space:]]/}"; URL="${URL/#webcal:\/\//https://}"
    case "$URL" in
      https://calendar.google.com/calendar/ical/*.ics) ;;
      *) echo "  That isn't a Google Calendar iCal address (it starts https://calendar.google.com/calendar/ical/ and ends .ics)."; exit 1 ;;
    esac
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$URL" || echo 0)
    if [ "$code" != 200 ]; then
      echo "  Google didn't hand it over (answer: $code)."
      case "$URL" in */public/*) echo "  That's the public address — it only works for a public calendar. Use the secret one.";; esac
      exit 1
    fi
    echo "  ✓ It works."
    ROOM_NEW_URL="$URL" edit add
    restart ;;
  list) edit list ;;
  clear) edit clear; echo "  ✓ Taken out."; restart ;;
  *) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
