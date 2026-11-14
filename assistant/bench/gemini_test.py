"""Ear test: Gemini Live — one model that hears and answers out loud — told to speak as an original cranky-genius
character (no real person's voice). A few Room-style requests (sent as text here; in Room it would hear your voice),
in a few of Gemini's voices; each answer played with how long it took to start talking. Nothing in Room changes.

Set up and run by scripts/gemini-test.sh (everything in ~/gemini-test). Needs "geminiKey" in config.json (Google AI
Studio). Costs a few rupees.
"""
import asyncio
import json
import os
import sys
import time
import wave

MODEL = os.environ.get("GEMINI_LIVE_MODEL", "gemini-3.1-flash-live-preview")
VOICES = ["Algenib", "Fenrir", "Charon", "Gacrux"]          # gravelly · excitable · informative · mature (Google's words)
ASKS = ["Dim the living room lights to thirty percent.",
        "What's the weather like in Bangalore this afternoon?",
        "Set a timer for ten minutes for the pasta."]
CHARACTER = ("You are the voice of a smart home panel in Bangalore. You are an original character: a brilliant, "
             "impatient, sarcastic old scientist with a raspy, gravelly voice who talks fast, sighs a lot, and finds "
             "everyday chores beneath him — but always does what's asked. Keep every answer to one or two short "
             "sentences. Speak English. Never claim to be or imitate any real person or existing fictional character. "
             "For this test, pretend the action was done, and make up plausible weather.")


def key():
    cfg = json.load(open(os.path.expanduser("~/.config/room/config.json")))
    return cfg.get("geminiKey") or cfg.get("googleKey")


async def ask(client, voice, text):
    from google.genai import types
    cfg = types.LiveConnectConfig(
        response_modalities=["AUDIO"], system_instruction=CHARACTER,
        speech_config=types.SpeechConfig(voice_config=types.VoiceConfig(
            prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=voice))),
        output_audio_transcription=types.AudioTranscriptionConfig())
    pcm, said, first = bytearray(), [], None
    async with client.aio.live.connect(model=MODEL, config=cfg) as s:
        t0 = time.perf_counter()
        await s.send_realtime_input(text=text)
        async for r in s.receive():
            sc = r.server_content
            if sc and sc.model_turn:
                for p in sc.model_turn.parts:
                    if p.inline_data and p.inline_data.data:
                        if first is None:
                            first = time.perf_counter() - t0
                        pcm += p.inline_data.data
            if sc and sc.output_transcription and sc.output_transcription.text:
                said.append(sc.output_transcription.text)
            if sc and sc.turn_complete:
                break
    return first, bytes(pcm), "".join(said).strip()


def main():
    k = key()
    if not k:
        raise SystemExit('no "geminiKey" in ~/.config/room/config.json (get one at aistudio.google.com)')
    from google import genai
    client = genai.Client(api_key=k)
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/gemini-test")
    only = os.environ.get("VOICES")
    n = 0
    for voice in (only.split(",") if only else VOICES):
        print(f"\n— {voice} —", flush=True)
        for text in ASKS:
            try:
                first, pcm, said = asyncio.run(ask(client, voice, text))
            except Exception as e:
                print(f"  ✗ {e}", flush=True); continue
            n += 1
            p = os.path.join(out, f"{n:02d}-{voice}.wav")
            with wave.open(p, "wb") as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000); w.writeframes(pcm)
            print(f"  you: {text}\n  it:  {said}\n  talking after {first or 0:.2f} s · {len(pcm) / 2 / 24000:.1f} s of speech",
                  flush=True)
            print(f"PLAY {p}", flush=True)                   # (the shell plays it, speaker lifted)


if __name__ == "__main__":
    main()
