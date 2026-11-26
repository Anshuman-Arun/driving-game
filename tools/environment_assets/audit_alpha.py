"""Checksum-pinned RGBA PNG alpha audit for the two existing UV-matched maps."""
import hashlib
import json
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[2]
PINNED = {
    "fern_fern_02_diff-fern_02_alpha.png": ("077638c74ae88184f8eba1dfc8608904eafd3272aa4d2e587f05109bd5b9c943", 906654, 163888),
    "fir_fir_sapling_medium_twigs_diff-fir_sapling_medium_twigs_alpha.png": ("83c7b1863d533a6e86e2d6b2509ad4ee883f8877c11b5549fee1f6bb5baa9603", 766435, 254645),
}


def check(ok, message):
    if not ok:
        raise ValueError(message)


def alpha_stats(data):
    check(data.startswith(b"\x89PNG\r\n\x1a\n"), "invalid PNG signature")
    offset, width, height, ended = 8, 0, 0, False
    parts = []
    while offset < len(data):
        check(offset + 12 <= len(data), "truncated PNG chunk")
        length, tag = struct.unpack_from(">I4s", data, offset)
        end = offset + 8 + length
        check(end + 4 <= len(data), "PNG chunk exceeds payload")
        check(zlib.crc32(data[offset+4:end]) == struct.unpack_from(">I", data, end)[0], "PNG CRC mismatch")
        payload = data[offset+8:end]
        if tag == b"IHDR":
            check(offset == 8 and length == 13, "invalid IHDR")
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", payload)
            check(0 < width * height <= 4_000_000 and (depth, color, compression, filtering, interlace) == (8, 6, 0, 0, 0), "requires bounded noninterlaced RGBA8 PNG")
        elif tag == b"IDAT":
            check(width > 0 and height > 0, "IDAT before IHDR")
            parts.append(payload)
        elif tag == b"IEND":
            check(length == 0 and end + 4 == len(data), "invalid IEND")
            ended = True
            break
        offset = end + 4
    check(ended and parts, "missing PNG chunks")
    stride = width * 4
    limit = height * (stride + 1)
    decoder = zlib.decompressobj()
    raw = decoder.decompress(b"".join(parts), limit + 1)
    check(len(raw) == limit and decoder.eof and not decoder.unconsumed_tail and not decoder.unused_data, "invalid or oversized PNG scanlines")
    prior = bytearray(stride)
    histogram = [0] * 256
    for y in range(height):
        start = y * (stride + 1)
        mode = raw[start]
        check(mode <= 4, "invalid PNG filter")
        row = bytearray(raw[start+1:start+1+stride])
        for x in range(stride):
            left = row[x-4] if x >= 4 else 0
            above = prior[x]
            corner = prior[x-4] if x >= 4 else 0
            if mode == 1:
                predict = left
            elif mode == 2:
                predict = above
            elif mode == 3:
                predict = (left + above) // 2
            elif mode == 4:
                p = left + above - corner
                pa, pb, pc = abs(p-left), abs(p-above), abs(p-corner)
                predict = left if pa <= pb and pa <= pc else above if pb <= pc else corner
            else:
                predict = 0
            row[x] = (row[x] + predict) & 255
        for value in row[3::4]:
            histogram[value] += 1
        prior = row
    total = width * height
    below = sum(histogram[:100])  # 99/255 < 0.39 <= 100/255.
    return {"width": width, "height": height, "below_scissor_039": below,
            "above_scissor_039": total - below, "coverage": (total-below)/total,
            "zero": histogram[0], "fully_opaque": histogram[255],
            "partial": total-histogram[0]-histogram[255]}


def audit(root=ROOT):
    output = []
    for name, (digest, size, above) in PINNED.items():
        path = root / "assets" / "premium_runtime" / name
        data = path.read_bytes()
        check(len(data) == size and hashlib.sha256(data).hexdigest() == digest, f"changed source texture: {name}")
        stats = alpha_stats(data)
        check(stats["width"] == stats["height"] == 1024 and stats["above_scissor_039"] == above and stats["below_scissor_039"] > 0, f"alpha coverage mismatch: {name}")
        output.append({"path": str(path.relative_to(root)), "sha256": digest, "bytes": size, **stats})
    return output


if __name__ == "__main__":
    print(json.dumps(audit(), indent=2))
