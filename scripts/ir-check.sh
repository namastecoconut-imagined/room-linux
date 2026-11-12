#!/usr/bin/env bash
# ir-check — is the Surface's IR camera (the face-login one, an OmniVision OV7251) visible to Linux? Changes nothing.
# Run with sudo (the kernel log needs it):   sudo bash ~/room/scripts/ir-check.sh
# Linux has had a driver for this sensor on Surfaces since 5.19 (ACPI id INT347E, through the IPU3's CIO2), but
# libcamera doesn't offer it as a camera (it's greyscale: there's nothing for the image processor to do), so it
# never shows in "cam --list". This looks underneath: the ACPI device, the driver, and the capture pipeline.
echo "== The IR sensor in the firmware (ACPI)"
found=0
for d in /sys/bus/acpi/devices/*; do
  hid=$(cat "$d/hid" 2>/dev/null) || continue
  case "$hid" in INT347E|OVTI7251|MSHW0122|INT3472|INT33BE|INT347A|MSHW012*)
    st=$(cat "$d/status" 2>/dev/null || echo "?")
    phys=$(readlink -f "$d/physical_node" 2>/dev/null || true)
    echo "  $hid  ($(basename "$d")) status $st${phys:+ → ${phys##*/}}"; found=1 ;;
  esac
done
[ $found = 1 ] || echo "  none of the camera ids found"

echo; echo "== Drivers"
for m in ov7251 ov5693 ov8865 ipu3_cio2 ipu3_imgu intel_skl_int3472_discrete intel_skl_int3472_tps68470; do
  if lsmod | grep -q "^$m "; then echo "  ✓ $m loaded"; else echo "  · $m not loaded"; fi
done
echo "  sensors the kernel bound:"
for n in /sys/bus/i2c/devices/*/name; do
  case "$(cat "$n")" in *ov*|*OV*|*7251*|*5693*|*8865*) echo "    $(cat "$n")  ($(basename "$(dirname "$n")"))";; esac
done

echo; echo "== Kernel messages about the cameras"
dmesg 2>/dev/null | grep -i -E 'ov7251|int347e|ov5693|ov8865|cio2|int3472|ipu3' | tail -25 | sed 's/^/  /' \
  || echo "  (run with sudo to read these)"

echo; echo "== The capture pipeline (media-ctl)"
if command -v media-ctl >/dev/null; then
  for m in /dev/media*; do
    media-ctl -d "$m" -p 2>/dev/null | grep -E '^- entity|device node name|-> |<- ' | grep -i -E 'entity|ov|cio2|csi|node' \
      | sed 's/^/  /' | head -40
  done
else
  echo "  media-ctl isn't installed: sudo dnf install -y v4l-utils   (then run this again)"
fi
