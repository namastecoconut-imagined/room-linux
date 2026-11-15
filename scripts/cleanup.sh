#!/usr/bin/env bash
# The cleanup from the audit (15 Nov) — what was chosen, nothing else. Shows what it will remove, asks, then removes.
#   sudo bash ~/room/scripts/cleanup.sh
# 1 the voice experiments' folders · 2 downloaded AI models (cache) · 3 Python package caches · 4 old crash reports
# (and a cap so they can't pile up again) · 5 Firefox's cache · 6 the older standard kernel (7.2.11; the newer standard
# one stays as the emergency backup, the Surface kernel is what runs).
# Not touched: ~/Projects, ~/room-wake-test, ~/room-echo-live, Room itself, your voice, Firefox's logins and settings.
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
[ "$(id -u)" = 0 ] || { echo "Run with sudo:  sudo bash ~/room/scripts/cleanup.sh"; exit 1; }
U=${SUDO_USER:-$(id -un)}
H=$(getent passwd "$U" | cut -d: -f6)
as() { sudo -u "$U" env HOME="$H" "$@"; }
size() { local e=(); for f in "$@"; do [ -e "$f" ] && e+=("$f"); done; [ ${#e[@]} -gt 0 ] && du -shc "${e[@]}" 2>/dev/null | tail -1 | cut -f1 || echo nothing; }
OLDK=$(rpm -qa 'kernel*' | grep -- '-7\.2\.11-300\.fc45' | grep -v "$(uname -r)" | sort)

echo "Before: $(df -h / | awk 'NR==2 {print $3 " used, " $4 " free"}')"
echo
echo "This will remove:"
echo "  1  the experiments' folders: $(ls -d "$H"/rvc-test "$H"/piper-test "$H"/gemini-test 2>/dev/null | xargs -r -n1 basename | tr '\n' ' ')($(size "$H"/rvc-test "$H"/piper-test "$H"/gemini-test))"
echo "  2  downloaded AI models: ~/.cache/huggingface, ~/.cache/torch ($(size "$H"/.cache/huggingface "$H"/.cache/torch))"
echo "  3  Python package caches: uv's and pip's ($(size "$H"/.cache/uv "$H"/.cache/pip))"
echo "  4  old crash reports ($(size /var/lib/systemd/coredump)), from:"
coredumpctl list --no-pager --no-legend 2>/dev/null | awk '{print $NF}' | sort | uniq -c | sort -rn | head -6 | sed 's/^/        /'
echo "     and from now on they're capped at 200 MB in all"
echo "  5  Firefox's cache ($(size "$H"/.cache/mozilla)) — logins, bookmarks and settings stay"
echo "  6  the older standard kernel: $(echo ${OLDK:-already gone})"
echo
echo "Left alone: ~/Projects, ~/room-wake-test, ~/room-echo-live. ~/Projects holds:"
ls -A "$H/Projects" 2>/dev/null | head -15 | sed 's/^/    /'; echo "    ($(size "$H/Projects"))"
echo
read -r -p "Go ahead? [y/N] " a </dev/tty
[ "$a" = y ] || [ "$a" = Y ] || { echo "Nothing changed."; exit 0; }

echo "▸ 1 the experiments' folders"
as bash "$HERE/scripts/experiments.sh" clean 2>&1 | grep -E '✓|removed|!' | sed 's/^/  /'
echo "▸ 2 downloaded AI models"
rm -rf "$H/.cache/huggingface" "$H/.cache/torch"
echo "▸ 3 Python package caches"
as bash -lc 'command -v uv >/dev/null && uv cache clean -q' 2>/dev/null; rm -rf "$H/.cache/pip" "$H/.cache/uv"
echo "▸ 4 old crash reports, and the cap"
rm -f /var/lib/systemd/coredump/*
mkdir -p /etc/systemd/coredump.conf.d
printf '# Room (cleanup.sh, 15 Nov): crash reports kept small — 200 MB at most, never past 1 GB free\n[Coredump]\nMaxUse=200M\nKeepFree=1G\n' \
  > /etc/systemd/coredump.conf.d/room.conf
echo "▸ 5 Firefox's cache"
if pgrep -u "$U" -x firefox >/dev/null; then echo "  Firefox is open — skipped (close it and run this again)"; else rm -rf "$H/.cache/mozilla"; fi
echo "▸ 6 the older standard kernel"
if [ -n "$OLDK" ]; then dnf remove -y -q $OLDK >/dev/null && echo "  removed: $(echo $OLDK | wc -w) packages"; else echo "  already gone"; fi
echo
echo "After: $(df -h / | awk 'NR==2 {print $3 " used, " $4 " free"}') · kernels left: $(rpm -q kernel kernel-surface 2>/dev/null | tr '\n' ' ')"
echo "Room is untouched — nothing restarted."
