"""Packs a microWakeWord .tflite and its JSON manifest into one image for the
raw "model" partition. The firmware mmaps the partition and reads this layout:

    0   "ORWW"
    4   u32 format version, 1
    8   u32 json length (without the terminating zero)
    12  u32 model length
    16  u32 model offset from the start of the image, 16 byte aligned
    32  json, zero terminated, then padding, then the .tflite

    python pack_model.py model.tflite model.json out.bin
"""

import json
import struct
import sys

PARTITION_SIZE = 0x80000
HEADER = 32


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: pack_model.py <model.tflite> <model.json> <out.bin>")
    tflite_path, json_path, out_path = sys.argv[1:4]

    model = open(tflite_path, "rb").read()
    manifest = open(json_path, "rb").read()
    parsed = json.loads(manifest)
    micro = parsed.get("micro", {})
    for key in ("probability_cutoff", "feature_step_size", "sliding_window_size", "tensor_arena_size"):
        if key not in micro:
            sys.exit(f"pack_model: manifest is missing micro.{key}")

    model_off = (HEADER + len(manifest) + 1 + 15) & ~15
    total = model_off + len(model)
    if total > PARTITION_SIZE:
        sys.exit(f"pack_model: image is {total} bytes, partition holds {PARTITION_SIZE}")

    header = b"ORWW" + struct.pack("<IIII", 1, len(manifest), len(model), model_off)
    header += bytes(HEADER - len(header))
    image = header + manifest + b"\0"
    image += bytes(model_off - len(image)) + model

    with open(out_path, "wb") as f:
        f.write(image)
    print(f"pack_model: {parsed.get('wake_word', '?')}: model {len(model)} bytes, "
          f"manifest {len(manifest)} bytes, image {len(image)} bytes -> {out_path}")


if __name__ == "__main__":
    main()
