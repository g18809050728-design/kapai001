"""Slice a prepared G6 image atlas without resizing or removing backgrounds.

Rows/columns are zero-based. Cell boundaries use floor(index * image_size /
cell_count), including the last pixel of uneven grids. Insets round UP on each
side. Aspect crops round DOWN and center; an odd extra pixel is discarded from
the right/bottom. All reported boxes are [left, top, right, bottom), as in Pillow.
Only catalogued, non-empty slots are exported. Outputs remain unreviewed candidates.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from fractions import Fraction
import hashlib
from io import BytesIO
import json
import math
from pathlib import Path, PurePosixPath, PureWindowsPath
import sys

try:
    from PIL import Image
except ImportError:
    print("Missing Pillow. Install: python -m pip install -r requirements-g6.txt", file=sys.stderr)
    raise SystemExit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def positive_int(value: object, label: str) -> int:
    require(type(value) is int and value > 0, f"{label} must be a positive integer")
    return value


def finite_number(value: object, label: str) -> float:
    require(type(value) in (int, float), f"{label} must be a number")
    require(math.isfinite(value), f"{label} must be finite")
    return value


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def relative_png(value: object) -> Path:
    require(isinstance(value, str) and bool(value), "output_name must be a non-empty string")
    require("\\" not in value, f"Use forward slashes in output_name: {value}")
    path = PurePosixPath(value)
    require(not path.is_absolute() and not PureWindowsPath(value).drive,
            f"Absolute output_name is forbidden: {value}")
    require(all(part not in ("", ".", "..") for part in value.split("/")),
            f"Invalid output path component: {value}")
    require(path.parts[0].casefold() != "slicing.json",
            "slicing.json is reserved for the slicing manifest")
    reserved = {"CON", "PRN", "AUX", "NUL"} | {
        f"{prefix}{index}" for prefix in ("COM", "LPT") for index in range(1, 10)
    }
    for part in path.parts:
        require(not any(char in part for char in '<>:"|?*') and
                not any(ord(char) < 32 for char in part) and not part.endswith((".", " ")),
                f"Invalid portable filename: {value}")
        require(part.split(".")[0].upper() not in reserved, f"Reserved filename: {value}")
    require(path.suffix.lower() == ".png", f"output_name must end in .png: {value}")
    return Path(*path.parts)


def build_plan(catalog: dict, batch_id: str, variant: str, size: tuple[int, int],
               output_dir: Path, allow_size_mismatch: bool) -> tuple[dict, list[dict], list[str]]:
    require(isinstance(catalog, dict), "Catalog root must be an object")
    assets, batches = catalog.get("assets"), catalog.get("batches")
    require(isinstance(assets, list) and isinstance(batches, list),
            "Catalog requires assets and batches arrays")
    asset_paths, names = {}, set()
    for asset in assets:
        require(isinstance(asset, dict), "Asset entry must be an object")
        asset_id = asset.get("id")
        require(isinstance(asset_id, str) and bool(asset_id), "Asset id must be non-empty")
        require(asset_id not in asset_paths, f"Duplicate asset id: {asset_id}")
        path = relative_png(asset.get("output_name"))
        name = path.as_posix().casefold()
        require(name not in names, f"Duplicate output_name: {path}")
        names.add(name)
        asset_paths[asset_id] = path
    batch_lookup = {}
    for batch in batches:
        require(isinstance(batch, dict), "Batch entry must be an object")
        identifier = batch.get("id")
        require(isinstance(identifier, str) and bool(identifier), "Batch id must be non-empty")
        require(identifier not in batch_lookup, f"Duplicate batch id: {identifier}")
        batch_lookup[identifier] = batch
    require(batch_id in batch_lookup, f"Unknown batch: {batch_id}")
    batch = batch_lookup[batch_id]
    variants = batch.get("variants")
    require(isinstance(variants, dict) and isinstance(variants.get(variant), dict),
            f"Missing variant {variant} in batch {batch_id}")
    dimensions = variants[variant]
    expected = (positive_int(dimensions.get("width"), "variant.width"),
                positive_int(dimensions.get("height"), "variant.height"))
    warnings = []
    if size != expected:
        require(allow_size_mismatch,
                f"Input size {size} differs from {variant} size {expected}; "
                "use --allow-size-mismatch only after checking the full grid")
        warnings.append(f"Actual size {size} differs from expected {expected}; "
                        "coordinates use actual size. No upscaling was performed.")
    columns = positive_int(batch.get("columns"), "columns")
    rows = positive_int(batch.get("rows"), "rows")
    require(size[0] >= columns and size[1] >= rows, "Grid is larger than input pixels")
    crop = batch.get("crop")
    require(isinstance(crop, dict), "Batch crop must be an object")
    inset = finite_number(crop.get("inset_ratio"), "inset_ratio")
    require(0 <= inset < 0.5, "inset_ratio must be in [0, 0.5)")
    ratio_value = crop.get("aspect_ratio")
    ratio = None
    if ratio_value is not None:
        require(isinstance(ratio_value, list) and len(ratio_value) == 2,
                "aspect_ratio must be [width, height] or null")
        for number in ratio_value:
            require(finite_number(number, "aspect_ratio component") > 0,
                    "aspect_ratio components must be positive")
        ratio = Fraction(str(ratio_value[0])) / Fraction(str(ratio_value[1]))
    slots = batch.get("slots")
    require(isinstance(slots, list), "Batch slots must be an array")
    seen_cells, seen_assets, plan = set(), set(), []
    for slot in slots:
        require(isinstance(slot, dict), "Slot must be an object")
        row, column = slot.get("row"), slot.get("column")
        require(type(row) is int and type(column) is int and
                0 <= row < rows and 0 <= column < columns,
                f"Out-of-bounds zero-based slot: row={row}, column={column}")
        require((row, column) not in seen_cells, f"Duplicate slot: ({row}, {column})")
        seen_cells.add((row, column))
        asset_id = slot.get("asset_id")
        if asset_id is None or asset_id == "":
            continue
        require(isinstance(asset_id, str) and asset_id in asset_paths,
                f"Unknown asset_id in slot: {asset_id}")
        require(asset_id not in seen_assets, f"Duplicate asset in selected batch: {asset_id}")
        seen_assets.add(asset_id)
        cell = [column * size[0] // columns, row * size[1] // rows,
                (column + 1) * size[0] // columns, (row + 1) * size[1] // rows]
        inset_x = math.ceil((cell[2] - cell[0]) * inset)
        inset_y = math.ceil((cell[3] - cell[1]) * inset)
        box = [cell[0] + inset_x, cell[1] + inset_y,
               cell[2] - inset_x, cell[3] - inset_y]
        width, height = box[2] - box[0], box[3] - box[1]
        require(width > 0 and height > 0, f"Inset removes all pixels for {asset_id}")
        if ratio is not None:
            if width * ratio.denominator > height * ratio.numerator:
                crop_width = height * ratio.numerator // ratio.denominator
                box[0] += (width - crop_width) // 2
                box[2] = box[0] + crop_width
            else:
                crop_height = width * ratio.denominator // ratio.numerator
                box[1] += (height - crop_height) // 2
                box[3] = box[1] + crop_height
        require(box[2] > box[0] and box[3] > box[1],
                f"Aspect crop removes all pixels for {asset_id}")
        path = asset_paths[asset_id]
        target = output_dir / path
        require(target.resolve().is_relative_to(output_dir), f"Output escapes directory: {target}")
        require(not target.exists() and not target.is_symlink(), f"Refusing to overwrite: {target}")
        plan.append({"asset_id": asset_id, "row": row, "column": column,
                     "cell_box": cell, "crop_box": box, "output_file": path.as_posix(),
                     "width": box[2] - box[0], "height": box[3] - box[1]})
    require(bool(plan), "Selected batch has no populated slots")
    report_path = output_dir / "slicing.json"
    require(not report_path.exists() and not report_path.is_symlink(),
            f"Refusing to overwrite: {report_path}")
    return batch, plan, warnings


def run(args: argparse.Namespace) -> dict:
    catalog_path = args.catalog.resolve()
    source_path = args.input.resolve()
    output_dir = args.output_dir.resolve()
    catalog_bytes = catalog_path.read_bytes()
    catalog = json.loads(catalog_bytes.decode("utf-8-sig"))
    source_bytes = source_path.read_bytes()
    with Image.open(BytesIO(source_bytes)) as original:
        require(getattr(original, "n_frames", 1) == 1, "Animated/multi-frame input is unsupported")
        original.load()
        batch, plan, warnings = build_plan(catalog, args.batch, args.variant, original.size,
                                           output_dir, args.allow_size_mismatch)
        has_alpha = "A" in original.getbands()
        transparency_metadata = "transparency" in original.info
        image = original.convert("RGBA" if has_alpha or transparency_metadata else "RGB")
        transparent_pixels = (image.mode == "RGBA" and
                              image.getchannel("A").getextrema()[0] < 255)
        report = {
            "schema_version": 1, "created_at": datetime.now(timezone.utc).isoformat(),
            "batch_id": args.batch, "variant": args.variant, "dry_run": args.dry_run,
            "resource_status": "candidate_unreviewed", "catalog_file": str(catalog_path),
            "catalog_sha256": sha256(catalog_bytes), "source_file": str(source_path),
            "source_sha256": sha256(source_bytes), "source_size": list(original.size),
            "expected_size": batch["variants"][args.variant], "output_dir": str(output_dir),
            "grid": {"columns": batch["columns"], "rows": batch["rows"]},
            "crop": batch["crop"],
            "rounding": {"grid": "floor(index * size / count)", "inset": "ceil per side",
                         "aspect": "floor; centered; odd remainder on right/bottom",
                         "boxes": "[left, top, right, bottom), input pixel coordinates"},
            "source_mode": original.mode, "source_has_alpha_channel": has_alpha,
            "source_has_transparency_metadata": transparency_metadata,
            "source_contains_transparent_pixels": transparent_pixels,
            "output_mode": image.mode, "background_removed": False, "resized": False,
            "warnings": warnings, "slices": plan,
        }
        if args.dry_run:
            return report
        created_files = []
        try:
            for item in plan:
                target = output_dir / item["output_file"]
                target.parent.mkdir(parents=True, exist_ok=True)
                # Exclusive creation prevents accidental replacement, including reruns.
                with BytesIO() as buffer:
                    image.crop(item["crop_box"]).save(buffer, format="PNG")
                    data = buffer.getvalue()
                with target.open("xb") as handle:
                    created_files.append(target)
                    handle.write(data)
                item["sha256"] = sha256(data)
                item["contains_transparent_pixels"] = (
                    image.mode == "RGBA" and
                    image.getchannel("A").crop(item["crop_box"]).getextrema()[0] < 255
                )
            report_path = output_dir / "slicing.json"
            with report_path.open("x", encoding="utf-8", newline="\n") as handle:
                created_files.append(report_path)
                json.dump(report, handle, ensure_ascii=False, indent=2, allow_nan=False)
                handle.write("\n")
        except BaseException:
            for path in reversed(created_files):
                path.unlink(missing_ok=True)
            raise
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--batch", required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--variant", choices=("high", "standard"), default="high")
    parser.add_argument("--allow-size-mismatch", action="store_true")
    parser.add_argument("--dry-run", action="store_true", help="Print crop plan without writing any files")
    args = parser.parse_args()
    try:
        report = run(args)
        for warning in report["warnings"]:
            print(f"WARNING: {warning}", file=sys.stderr)
        print(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False))
        return 0
    except (ValueError, TypeError, KeyError, OSError, OverflowError,
            Image.DecompressionBombError) as exc:
        print(f"G6 atlas error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
