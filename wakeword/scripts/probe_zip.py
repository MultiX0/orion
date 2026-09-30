"""Lists what is inside a remote zip without downloading it.

Reads the central directory with HTTP range requests, so a multi gigabyte
archive costs a few kilobytes to inspect. Used to plan a partial fetch of the
microWakeWord negative sets when the whole archive does not fit on disk.

Usage:
    python scripts/probe_zip.py https://huggingface.co/datasets/kahrendt/microwakeword/resolve/main/speech.zip
"""

import io
import sys
import urllib.request
import zipfile


class RangeFile(io.RawIOBase):
    """A read-only file over HTTP that fetches only the bytes asked for."""

    def __init__(self, url):
        self.url = url
        self.pos = 0
        self.fetched = 0
        request = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(request) as response:
            self.url = response.geturl()
            self.size = int(response.headers["Content-Length"])

    def seek(self, offset, whence=io.SEEK_SET):
        if whence == io.SEEK_SET:
            self.pos = offset
        elif whence == io.SEEK_CUR:
            self.pos += offset
        else:
            self.pos = self.size + offset
        return self.pos

    def tell(self):
        return self.pos

    def readable(self):
        return True

    def seekable(self):
        return True

    def readinto(self, buffer):
        n = len(buffer)
        if n == 0 or self.pos >= self.size:
            return 0
        end = min(self.pos + n, self.size) - 1
        request = urllib.request.Request(self.url, headers={"Range": "bytes=%d-%d" % (self.pos, end)})
        with urllib.request.urlopen(request) as response:
            data = response.read()
        buffer[: len(data)] = data
        self.pos += len(data)
        self.fetched += len(data)
        return len(data)


def main():
    for url in sys.argv[1:]:
        remote = RangeFile(url)
        print("%s: %.1f MB" % (url.rsplit("/", 1)[-1], remote.size / 1e6))
        with zipfile.ZipFile(io.BufferedReader(remote, buffer_size=1 << 20)) as archive:
            for info in archive.infolist():
                method = {0: "stored", 8: "deflate"}.get(info.compress_type, str(info.compress_type))
                print("  %-60s %10.1f MB  %8s  at %d" % (
                    info.filename, info.file_size / 1e6, method, info.header_offset))
        print("  bytes fetched to list it: %d" % remote.fetched)


if __name__ == "__main__":
    main()
