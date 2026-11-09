#!/usr/bin/env bash
# What room-spotify.service runs: Spotify Soloist (Spotify's own headless Spotify Connect player) as the speaker "Room".
# Soloist builds stop working 90 days after they're built, so this fetches a fresh one whenever the copy here is over
# 30 days old or says it has expired — nothing to remember.
set -u
BIN="$HOME/.local/bin/soloist"
DATA="$HOME/.local/share/room/soloist"
mkdir -p "$DATA/cache" "$HOME/.local/bin"
# shellcheck disable=SC1091
[ -f "$HOME/.config/room/soloist.env" ] && . "$HOME/.config/room/soloist.env"
if [ -z "${SOLOIST_API_KEY:-}" ]; then
  echo "No Soloist API key — run: bash ~/room/scripts/spotify-connect.sh" >&2
  exit 1
fi

fetch() {
  local arch tmp
  case "$(uname -m)" in x86_64) arch=x86_64 ;; aarch64) arch=arm64 ;; armv7l) arch=arm32 ;; *) echo "unsupported $(uname -m)" >&2; return 1 ;; esac
  tmp="$(mktemp -d)"
  if curl -fsSL -o "$tmp/s.tgz" "https://soloist-builds.spotifycdn.com/soloist_release_${arch}.tar.gz" \
     && tar -xzf "$tmp/s.tgz" -C "$tmp" && [ -x "$tmp/soloist" ]; then
    mv -f "$tmp/soloist" "$BIN.new" && mv -f "$BIN.new" "$BIN"
    echo "soloist: fetched $("$BIN" --version 2>/dev/null | head -1)"
  else
    echo "soloist: couldn't fetch a new build" >&2
  fi
  rm -rf "$tmp"
}

if [ ! -x "$BIN" ] || [ -n "$(find "$BIN" -mtime +30 2>/dev/null)" ]; then
  fetch
else
  "$BIN" --version >/dev/null 2>&1; [ $? -eq 10 ] && fetch      # exit code 10: this build has expired
fi
[ -x "$BIN" ] || exit 1
exec "$BIN" --device-name "${ROOM_SPOTIFY_NAME:-Room}" --api-key "$SOLOIST_API_KEY" \
     --data-dir "$DATA" --cache-dir "$DATA/cache" --cache-size 200 --initial-volume 60
