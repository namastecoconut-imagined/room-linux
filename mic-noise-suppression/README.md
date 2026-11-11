# Mic noise suppression (RNNoise) — removed from Room, 11 Nov 2026

A PipeWire filter-chain that made a second input, "Surface Mic (Noise Suppressed)" (`surface_mic_ns`), from the
Surface Pro 6's raw mic (`alsa_input.pci-0000_00_1f.3.analog-stereo`), using RNNoise from
[werman/noise-suppression-for-voice](https://github.com/werman/noise-suppression-for-voice) (LADSPA build, not
packaged in Fedora). Lived in `~/.config/pipewire/pipewire.conf.d/mic-noise-suppression.conf`, plugin in
`~/.local/share/rnnoise/linux-rnnoise/ladspa/librnnoise_ladspa.so`. It sounded great for recordings and calls.

Why it was removed: on the kiosk nothing needed it. The assistant always used the raw mic (the noise-suppressed one
was worse for every speech-to-text option and for the wake word), and Room's loudness meter (screen wake on sound)
used it only by being the default mic — where its voice gate (VAD threshold 50 %) turned footsteps, doors and
movement into silence, so the screen didn't wake for them. It also cost ~14 % of every PipeWire audio cycle.

To bring it back: download the release zip again, put the LADSPA .so at the path above, copy this .conf to
`~/.config/pipewire/pipewire.conf.d/`, and restart PipeWire. (`pactl set-default-source surface_mic_ns` to make it the
default.)

KEPT (separate, costs nothing): the mic boost cap — `/etc/modprobe.d/surface-pro6-audio.conf` with
`options snd-hda-intel model=limit-mic-boost` (boost 3 clipped up to 19 % of samples; capped to 0–1).
