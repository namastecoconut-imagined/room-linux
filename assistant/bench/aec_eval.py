"""Echo-cancelling test, step 2: takes what the Surface was playing back out of the mic (WebRTC's echo canceller,
AEC3 — the one in Chrome and Meet — through LiveKit's build) on record_echo's recordings, and shows what it changed:

  assistant/.venv/bin/python -u -m assistant.bench.aec_eval ~/room-echo-test/<time>

  • how much music is left in the mic between your lines (dB, before → after)
  • how far behind the mic the music arrives (Bluetooth adds a lot)
  • "Alexa" scores (Room's own model) per line, before → after
  • Sarvam's words per line, before → after (if sarvamKey is in config.json)
It also saves the cleaned mic next to each recording (*_aec.wav) to listen to.
"""
import json
import os
import sys
import wave

import numpy as np

RATE, N = 16000, 160        # 10 ms frames (what the echo canceller takes)


def load(path):
    with wave.open(path) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768


def save(path, x):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def cancel(mic, ref):
    from livekit import rtc
    apm = rtc.AudioProcessingModule(echo_cancellation=True, high_pass_filter=True)
    out = np.zeros_like(mic)
    def frame(x):
        return rtc.AudioFrame(data=(np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes(), sample_rate=RATE,
                              num_channels=1, samples_per_channel=len(x))
    for i in range(0, len(mic) - N + 1, N):
        apm.process_reverse_stream(frame(ref[i:i + N]))
        f = frame(mic[i:i + N]); apm.process_stream(f)
        out[i:i + N] = np.frombuffer(f.data, np.int16) / 32768
    return out


def delay(mic, ref, most=0.6):
    """How far behind what's played the mic hears it (from the loudness envelopes)."""
    def env(x):
        k = len(x) // N
        return np.sqrt(np.mean(x[:k * N].reshape(k, N) ** 2, axis=1))
    a, b = env(mic), env(ref)
    n = min(len(a), len(b)); a, b = a[:n] - a[:n].mean(), b[:n] - b[:n].mean()
    best, lag = -1, 0
    for d in range(0, int(most * 100)):
        c = float(np.dot(a[d:], b[:n - d])) / (np.linalg.norm(a[d:]) * np.linalg.norm(b[:n - d]) + 1e-9)
        if c > best:
            best, lag = c, d
    return lag * 10, best


def db(x):
    return 10 * np.log10(float(np.mean(x ** 2)) + 1e-12)


def main():
    folder = os.path.expanduser(sys.argv[1]) if len(sys.argv) > 1 else sys.exit(__doc__)
    plan = json.load(open(os.path.join(folder, "prompts.json")))
    cp = os.path.expanduser("~/.config/room/config.json")
    cfg = json.load(open(cp)) if os.path.exists(cp) else {}
    key = cfg.get("sarvamKey") or (cfg.get("voiceSettings") or {}).get("sarvamKey")
    from ..listen import Wake, sarvam
    w = Wake(cfg.get("assistant", {}).get("wakeThreshold"))
    for tag, beeps in plan.items():
        mic = load(os.path.join(folder, f"{tag}_mic.wav"))
        refs = [load(os.path.join(folder, f)) for f in sorted(os.listdir(folder)) if f.startswith(f"{tag}_ref_")]
        n = min([len(mic)] + [len(r) for r in refs])
        mic = mic[:n]; ref = np.sum([r[:n] for r in refs], axis=0) if refs else np.zeros(n, np.float32)
        out = cancel(mic, ref)
        save(os.path.join(folder, f"{tag}_aec.wav"), out)
        ms, corr = delay(mic, ref)
        # "between your lines": the 1.2 s before each beep (just music, and the beep's own echo is long gone)
        gaps = np.concatenate([np.arange(max(0, int((b["at"] - 1.4) * RATE)), int((b["at"] - 0.2) * RATE)) for b in beeps])
        gaps = gaps[gaps < n]
        print(f"\n== {tag}: music in the mic between lines {db(mic[gaps]):6.1f} dB → {db(out[gaps]):6.1f} dB "
              f"(removed {db(mic[gaps]) - db(out[gaps]):.1f} dB) · the mic hears the music {ms} ms late (match {corr:.2f})")
        for b in beeps:
            s, e = int((b["at"] + 0.15) * RATE), min(n, int((b["at"] + 6.0) * RATE))
            row = []
            for x in (mic, out):
                w.reset(); seg = (np.clip(x[s:e], -1, 1) * 32767).astype(np.int16)
                best = max(w.score(seg[i:i + 1280]) for i in range(0, len(seg) - 1279, 1280))
                words = ""
                if key:
                    try:
                        words = sarvam(seg, key)
                    except Exception as ex:
                        words = f"({ex})"
                row.append((best, words))
            print(f"  \"{b['said']}\"\n     before: Alexa {row[0][0]:.2f} · {row[0][1]!r}\n     after:  Alexa {row[1][0]:.2f} · {row[1][1]!r}")
    print(f"\nThe cleaned mic is saved as *_aec.wav in {folder} — have a listen.")


if __name__ == "__main__":
    main()
