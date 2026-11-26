"""Prepare versioned downloads for a single-threaded Godot Web export."""

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil


CHUNK_SIZE = 8 * 1024 * 1024
ENGINE_FILES = (
    "index.js", "index.wasm", "index.audio.worklet.js",
    "index.audio.position.worklet.js",
)
SHELL_FILES = (
    "index.html", "index.pck", "index.png", "index.icon.png",
    "index.apple-touch-icon.png", "game-shell.css", "game-shell.js",
    "game-shell.woff2", "account-campus.webp", "accounts.js", "OFL.txt",
)


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest()


def link(source, destination):
    try:
        os.link(source, destination)
    except FileExistsError:
        if not os.path.samefile(source, destination) and digest(source) != digest(destination):
            raise


def prepare(source, output, pack=None):
    html = (source / "index.html").read_text(encoding="utf-8")
    script_tag = '<script src="index.js"></script>'
    start_call = "engine.startGame({"
    if html.count(script_tag) != 1 or html.count(start_call) != 1:
        raise ValueError("Expected the standard Godot Web entry page. Export it again first.")

    output.mkdir(parents=True, exist_ok=True)
    pack = pack or source / "index.pck"
    html, count = re.subn(r'("index\.pck":)\d+', lambda match: match[1] + str(pack.stat().st_size), html)
    if count != 1:
        raise ValueError("Expected the original pack byte count in the Godot entry page")
    assets = output / "game-assets"
    wasm_gzip = source / "index.wasm.gz"
    if output != source:
        for name in (*ENGINE_FILES, *SHELL_FILES, wasm_gzip.name):
            if name not in ("index.html", "index.pck"):
                link(source / name, output / name)
        link(pack, output / "index.pck")

    engine_hash = hashlib.sha256()
    for name in ENGINE_FILES:
        engine_hash.update(bytes.fromhex(digest(source / name)))
    engine_dir = assets / engine_hash.hexdigest()
    engine_dir.mkdir(parents=True, exist_ok=True)
    for name in (*ENGINE_FILES, wasm_gzip.name):
        link(source / name, engine_dir / name)

    loader = Path(__file__).resolve().parents[1] / "web" / "pack-loader.js"
    loader_dir = assets / digest(loader)
    loader_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(loader, loader_dir / loader.name)

    pack_dir = assets / "pack"
    pack_dir.mkdir(parents=True, exist_ok=True)
    chunks = []
    with pack.open("rb") as pack_file:
        for data in iter(lambda: pack_file.read(CHUNK_SIZE), b""):
            name = hashlib.sha256(data).hexdigest() + ".bin"
            compressed = pack_dir / (name + ".gz")
            if not compressed.exists():
                temporary = compressed.with_suffix(".tmp")
                with temporary.open("wb") as fileobj:
                    with gzip.GzipFile(filename="", fileobj=fileobj, mode="wb",
                                       compresslevel=6, mtime=0) as stream:
                        stream.write(data)
                temporary.replace(compressed)
            chunks.append(["game-assets/pack/" + name, len(data)])
    if not chunks:
        raise ValueError("Empty Godot resource pack")

    engine = engine_dir.relative_to(output).as_posix() + "/index"
    loader_url = (loader_dir / loader.name).relative_to(output).as_posix()
    config = json.dumps({"engine": engine, "chunks": chunks}, separators=(",", ":"))
    html = html.replace(script_tag, f'<script src="{engine}.js"></script>\n'
                        f'<script src="{loader_url}"></script>')
    html = html.replace(start_call, f"KapaiWebPack.start(engine, GODOT_CONFIG, {config}, {{")
    temporary_html = output / "index.html.tmp"
    temporary_html.write_text(html, encoding="utf-8")
    temporary_html.replace(output / "index.html")
    print(f"Prepared {len(chunks)} pack chunks in {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--pack", type=Path, help="Use a different pack for a fresh release directory")
    args = parser.parse_args()
    if args.pack and (not args.output or args.source.resolve() == args.output.resolve()):
        parser.error("--pack requires a separate output directory")
    prepare(args.source.resolve(), (args.output or args.source).resolve(), args.pack)
