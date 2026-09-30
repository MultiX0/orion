"""Fetches one mmap folder out of a remote microWakeWord negative archive,
optionally only the first N gigabytes of it, without the zip touching disk.

The archives on Hugging Face are plain zips whose members are deflate streams,
so a member can be read with HTTP range requests and inflated straight into
its file. A RaggedMmap folder is one flat data.ninja plus small index folders
(starts, ends, shapes, flattened_shapes), so a prefix of the data file is a
valid set once the index is cut to the entries that fit inside it.

Usage:
    python scripts/fetch_negative_part.py \
        --zip https://huggingface.co/datasets/kahrendt/microwakeword/resolve/main/speech.zip \
        --member speech/training/voices_lav_mid_training_mmap \
        --out ~/orion_ww/negative_datasets/speech/training/voices_lav_mid_training_mmap \
        --max-gb 4
"""

import argparse
import io
import os
import shutil
import sys
import time
import zipfile

import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "scripts"))
from probe_zip import RangeFile  # noqa: E402

CHUNK = 8 << 20


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--zip", required=True)
    parser.add_argument("--member", required=True, help="folder inside the archive, no trailing slash")
    parser.add_argument("--out", required=True)
    parser.add_argument("--max-gb", type=float, default=None)
    args = parser.parse_args()

    from mmap_ninja import base
    from mmap_ninja import numpy as np_ninja
    from mmap_ninja.ragged import RaggedMmap

    out = os.path.expanduser(args.out)
    prefix = args.member.rstrip("/") + "/"
    remote = RangeFile(args.zip)
    archive = zipfile.ZipFile(io.BufferedReader(remote, buffer_size=CHUNK))
    members = [i for i in archive.infolist() if i.filename.startswith(prefix) and not i.is_dir()]
    data_member = [i for i in members if i.filename == prefix + "data.ninja"][0]
    print("%s: %d members, data.ninja %.2f GB uncompressed" % (
        args.member, len(members), data_member.file_size / 1e9), flush=True)

    os.makedirs(out, exist_ok=True)
    for info in members:
        if info is data_member:
            continue
        target = os.path.join(out, info.filename[len(prefix):])
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with archive.open(info) as src, open(target, "wb") as dst:
            shutil.copyfileobj(src, dst)

    limit = int(args.max_gb * 1e9) if args.max_gb else data_member.file_size
    limit = min(limit, data_member.file_size)
    written = 0
    started = time.time()
    with archive.open(data_member) as src, open(os.path.join(out, "data.ninja"), "wb") as dst:
        while written < limit:
            chunk = src.read(min(CHUNK, limit - written))
            if not chunk:
                break
            dst.write(chunk)
            written += len(chunk)
            if written % (256 << 20) < CHUNK:
                elapsed = time.time() - started
                print("  %.2f GB written, %.1f MB/s" % (written / 1e9, written / 1e6 / max(elapsed, 1)), flush=True)
    print("data.ninja: %.2f GB in %.0f s, %.1f MB fetched over http" % (
        written / 1e9, time.time() - started, remote.fetched / 1e6), flush=True)

    dtype = np.dtype(base._file_to_str(os.path.join(out, "dtype.ninja")))
    elements = written // dtype.itemsize
    ends = np.array(np_ninja.open_existing(os.path.join(out, "ends")))
    starts = np.array(np_ninja.open_existing(os.path.join(out, "starts")))
    flattened = np.array(np_ninja.open_existing(os.path.join(out, "flattened_shapes")))
    keep = int(np.searchsorted(ends, elements, side="right"))
    total = len(ends)
    if keep < total:
        shapes_are_flat = bool(base._file_to_int(os.path.join(out, "shapes_are_flat.ninja")))
        if shapes_are_flat:
            shapes = np.array(np_ninja.open_existing(os.path.join(out, "shapes")))[:keep]
        else:
            ragged = RaggedMmap(os.path.join(out, "shapes"))
            shapes = [np.array(ragged[i]) for i in range(keep)]
        last = int(ends[keep - 1])
        for name in ("starts", "ends", "flattened_shapes", "shapes"):
            shutil.rmtree(os.path.join(out, name))
        np_ninja.from_ndarray(os.path.join(out, "starts"), starts[:keep].astype(np.int64))
        np_ninja.from_ndarray(os.path.join(out, "ends"), ends[:keep].astype(np.int64))
        np_ninja.from_ndarray(os.path.join(out, "flattened_shapes"), flattened[:keep].astype(np.int64))
        if shapes_are_flat:
            np_ninja.from_ndarray(os.path.join(out, "shapes"), shapes)
        else:
            RaggedMmap.from_lists(os.path.join(out, "shapes"), shapes)
        with open(os.path.join(out, "data.ninja"), "r+b") as f:
            f.truncate(last * dtype.itemsize)
        base._shape_to_file((last,), os.path.join(out, "shape.ninja"))
        print("index cut to %d of %d entries" % (keep, total), flush=True)

    check = RaggedMmap(out)
    first, last_entry = check[0], check[len(check) - 1]
    frames = sum(int(check.shapes[i][0]) for i in range(len(check)))
    print("ok: %d entries, first %s last %s, %.2f hours at 10 ms a frame" % (
        len(check), first.shape, last_entry.shape, frames * 0.01 / 3600), flush=True)


if __name__ == "__main__":
    main()
