"""Shrink Godot 4.7 Web exports while retaining resource paths and image dimensions."""

import argparse
from collections import Counter
from dataclasses import dataclass
import hashlib
from io import BytesIO
import json
from pathlib import Path
import re
import struct
import tempfile

from PIL import Image, ImageChops, ImageStat
import zstandard


FILE = struct.Struct("<QQ16sI")
TEXTURE_SOURCES = ("assets/cards/", "assets/art/")
TEXTURE_SUFFIXES = (".png.import", ".webp.import", ".jpg.import", ".jpeg.import")
TEXTURE_MIN_SIZE = 32 * 1024
MAX_RGB_RMS = 5.0
FONT_BLOCK_SIZE = 256 * 1024


@dataclass
class Entry:
    name: bytes
    offset: int
    size: int
    digest: bytes


def read_entries(stream):
    header = stream.read(112)
    version, major, minor, _, flags, base, directory = struct.unpack_from("<IIIIIQQ", header, 4)
    if header[:4] != b"GDPC" or (version, major, minor, flags, base) != (4, 4, 7, 2, 112):
        raise ValueError("Expected an unencrypted Godot 4.7 export pack")
    stream.seek(directory)
    count, = struct.unpack("<I", stream.read(4))
    entries = []
    for _ in range(count):
        length, = struct.unpack("<I", stream.read(4))
        name = stream.read(length)
        offset, size, digest, flags = FILE.unpack(stream.read(FILE.size))
        if flags or base + offset + size > directory:
            raise ValueError(f"Unsupported pack entry {name!r}")
        entries.append(Entry(name, offset, size, digest))
    return header, entries


def get_data(stream, entry, base):
    stream.seek(base + entry.offset)
    data = stream.read(entry.size)
    if hashlib.md5(data).digest() != entry.digest:
        raise ValueError(f"Invalid pack resource checksum {entry.name!r}")
    return data


def compress_texture(data, source):
    # Godot GST2, version 1, one lossless WebP image. Leave other layouts intact.
    if len(data) < TEXTURE_MIN_SIZE or data[:8] != b"GST2\x01\x00\x00\x00":
        return data, None
    storage, width, height, mipmaps, channels, length = struct.unpack_from("<IHHIII", data, 36)
    if (storage != 2 or mipmaps != 0 or channels not in (4, 5)
            or len(data) != length + 56 or data[56:60] != b"RIFF"
            or data[64:72] != b"WEBPVP8L"):
        return data, None
    image = Image.open(BytesIO(data[56:])).convert("RGBA")
    if image.size != (width, height):
        return data, None
    alpha = image.getchannel("A")
    opaque = alpha.getextrema() == (255, 255)
    original_rgb = image.convert("RGB")
    for quality in (92, 96):
        output = BytesIO()
        source_image = original_rgb if channels == 4 else image
        source_image.save(output, format="WEBP", quality=quality, method=4)
        encoded = output.getvalue()
        if len(encoded) + 56 >= len(data) * 0.95:
            return data, None
        decoded = Image.open(BytesIO(encoded)).convert("RGBA")
        if decoded.size != image.size or ImageChops.difference(alpha, decoded.getchannel("A")).getbbox():
            continue
        decoded_rgb = decoded.convert("RGB")
        if not opaque:
            black = Image.new("RGB", image.size)
            expected = Image.composite(original_rgb, black, alpha)
            actual = Image.composite(decoded_rgb, black, alpha)
        else:
            expected, actual = original_rgb, decoded_rgb
        rms = max(ImageStat.Stat(ImageChops.difference(expected, actual)).rms)
        if rms <= MAX_RGB_RMS:
            detail = {"path": source, "before": len(data), "after": len(encoded) + 56,
                      "rms": round(rms, 3), "width": width, "height": height, "quality": quality}
            return data[:52] + struct.pack("<I", len(encoded)) + encoded, detail
    return data, None


def decompress_font(data):
    mode, block_size, size = struct.unpack_from("<III", data, 4)
    if data[:4] != b"RSCC" or mode != 2 or not block_size:
        raise ValueError("Expected a Zstandard-compressed Godot font")
    count = size // block_size + 1
    sizes = struct.unpack_from(f"<{count}I", data, 16)
    offset = 16 + 4 * count
    raw = bytearray()
    decoder = zstandard.ZstdDecompressor()
    for length in sizes:
        raw.extend(decoder.decompress(data[offset:offset + length], max_output_size=block_size))
        offset += length
    if len(raw) != size or data[offset:] != b"RSCC":
        raise ValueError("Invalid Godot font block table")
    return raw


def compress_font(data):
    raw = decompress_font(data)
    encoder = zstandard.ZstdCompressor(level=12)
    blocks = [encoder.compress(raw[offset:offset + FONT_BLOCK_SIZE])
              for offset in range(0, len(raw) + 1, FONT_BLOCK_SIZE)]
    result = (b"RSCC" + struct.pack("<III", 2, FONT_BLOCK_SIZE, len(raw))
              + b"".join(struct.pack("<I", len(block)) for block in blocks)
              + b"".join(blocks) + b"RSCC")
    if decompress_font(result) != raw:
        raise ValueError("Font data changed during recompression")
    return result if len(result) < len(data) else data


def write_pack(source, output):
    with source.open("rb") as stream, tempfile.NamedTemporaryFile(dir=output.parent) as target:
        header, entries = read_entries(stream)
        target.write(header)
        base = len(header)
        textures = {}
        for entry in entries:
            name = entry.name.rstrip(b"\0").decode("utf-8")
            if name.startswith(TEXTURE_SOURCES) and name.endswith(TEXTURE_SUFFIXES):
                remap = get_data(stream, entry, base).decode("utf-8")
                match = re.search(r'^path="res://([^"]+\.ctex)"$', remap, re.MULTILINE)
                if match:
                    textures[match.group(1)] = name[:-7]

        sizes = Counter()
        images = []
        fonts = []
        for entry in sorted(entries, key=lambda item: item.offset):
            name = entry.name.rstrip(b"\0").decode("utf-8")
            original = get_data(stream, entry, base)
            data = original
            if name in textures:
                data, detail = compress_texture(original, textures[name])
                if detail:
                    images.append(detail)
            elif (name.startswith(".godot/imported/Noto") and name.endswith(".fontdata")
                  and original[:8] == b"RSCC\x02\x00\x00\x00"):
                data = compress_font(original)
                fonts.append({"path": name, "before": len(original), "after": len(data)})
            sizes["original_entry_bytes"] += len(original)
            sizes["optimized_entry_bytes"] += len(data)
            entry.offset = target.tell() - base
            entry.size = len(data)
            entry.digest = hashlib.md5(data).digest()
            target.write(data)
            target.write(bytes(-target.tell() % 16))

        directory = target.tell()
        target.write(struct.pack("<I", len(entries)))
        for entry in entries:
            target.write(struct.pack("<I", len(entry.name)))
            target.write(entry.name)
            target.write(FILE.pack(entry.offset, entry.size, entry.digest, 0))
        pack_bytes = target.tell()
        target.seek(32)
        target.write(struct.pack("<Q", directory))
        target.flush()
        target_path = Path(target.name)
        target_path.chmod(0o644)
        # Link the complete temporary file and atomically replace any original.
        replacement = target_path.with_suffix(".pck")
        replacement.hardlink_to(target_path)
        replacement.replace(output)
    return {**sizes, "pack_bytes": pack_bytes, "entries": len(entries), "textures": images, "fonts": fonts}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    report = write_pack(args.source, args.output or args.source)
    if args.report:
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Optimized {len(report['textures'])} textures and {len(report['fonts'])} fonts "
          f"in {report['pack_bytes']:,} pack bytes")
