# Dolby speaker tuning (removed from Room, 11 Nov 2026)

The Surface Pro 6 speaker tuning: Microsoft's `DAX2Preset10CC_SPK` (from the Surface driver package, `HDXSSTM.inf`,
codec `10ec:10cc`) converted with `speaker-tuning-to-easyeffects` into a PipeWire filter-chain, regenerated with
virtual bass. `Dolby_Balanced.conf` is the final version (with Room's end limiter, `final_limit`); `.conf.orig` is
before that limiter was added; `Dolby_Balanced.irs` is the impulse response the convolvers load.

It lived in `~/.config/pipewire/pipewire.conf.d/` as a *smart filter* in front of the built-in speakers, and needed
the Calf (Saturator) and LSP (filter, limiter, multiband compressor) LV2 plugins plus lilv.

Why it was removed: it cost 44–51 % of every PipeWire audio cycle at the CPU's low clock (about half a core, all
day — it processed silence too), and that realtime load got PipeWire killed (RLIMIT_RTTIME) and made rtkit demote
all realtime threads. Music mostly plays on a Bluetooth speaker, which has its own tuning.

To bring it back: copy the three files to `~/.config/pipewire/pipewire.conf.d/` (fix the `.irs` path inside the
.conf if the user name differs), install `calf lsp-plugins-lv2 lilv` (and the PipeWire LV2 filter-chain module), and
restart PipeWire.
