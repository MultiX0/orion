#!/usr/bin/env bash
# Downloads the negative and augmentation data microWakeWord expects.
#
# Disk is the constraint on this machine, so we take only the small standard
# sets: the DiPCo dinner party spectrograms for hard speech negatives and the
# dinner party eval set for the false accepts per hour metric. The multi
# gigabyte speech.zip and no_speech.zip sets are replaced by locally generated
# speech and by an FMA music subset. Zips are deleted as soon as they unpack.
set -eu
WORK=${WORK:-$HOME/orion_ww}
NEG=$WORK/negative_datasets
mkdir -p "$NEG" "$WORK/mit_rirs" "$WORK/fma_16k"

say() { echo "--- $* ---"; df -h /mnt/c | tail -1; }

say start

# 1. DiPCo dinner party spectrograms, already in microWakeWord feature form.
# This WSL has no unzip, so python's zipfile module does the unpacking.
for name in dinner_party_eval dinner_party; do
  if [ ! -d "$NEG/$name" ]; then
    curl -L --no-progress-meter -o "$NEG/$name.zip" \
      "https://huggingface.co/datasets/kahrendt/microwakeword/resolve/main/$name.zip"
    python3 -m zipfile -e "$NEG/$name.zip" "$NEG"
    rm -f "$NEG/$name.zip"
    say "$name unpacked"
  fi
done

# 2. MIT environmental impulse responses, 16 kHz wav, for reverberation.
if [ -z "$(ls -A "$WORK/mit_rirs" 2>/dev/null)" ]; then
  curl -s "https://huggingface.co/api/datasets/davidscripka/MIT_environmental_impulse_responses/tree/main/16khz?recursive=true" \
    | tr '{' '\n' | grep -o '"path":"16khz/[^"]*\.wav"' | cut -d'"' -f4 > "$WORK/rir_list.txt"
  echo "rir files: $(wc -l < "$WORK/rir_list.txt")"
  while read -r p; do
    out="$WORK/mit_rirs/$(basename "$p")"
    [ -f "$out" ] || curl -sL -o "$out" \
      "https://huggingface.co/datasets/davidscripka/MIT_environmental_impulse_responses/resolve/main/$p"
  done < "$WORK/rir_list.txt"
  say "rirs downloaded"
fi

# 3. Free Music Archive extra small, used as background noise. We keep a
# subset only: 30 second tracks at 16 kHz add up fast.
if [ ! -f "$WORK/fma_xs.zip" ] && [ -z "$(ls -A "$WORK/fma_16k" 2>/dev/null)" ]; then
  curl -L --no-progress-meter -o "$WORK/fma_xs.zip" \
    "https://huggingface.co/datasets/mchl914/fma_xsmall/resolve/main/fma_xs.zip"
  say "fma zip downloaded"
fi
echo done
