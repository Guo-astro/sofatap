#!/usr/bin/env python3
"""Frame verified physical-device screenshots and edit real capture clips for ASC.

No phone control, network access, generated UI, screenshot animation, or upload.
Requires Python 3.10+, Pillow, ffmpeg and ffprobe. See docs/app-store/media-production.md.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont

BACKGROUND = (9, 17, 20)
FOREGROUND = (234, 249, 241)
MINT = (166, 239, 205)
MUTED = (156, 183, 174)
SCREENSHOT_SIZES = ((1320, 2868), (1206, 2622))
PREVIEW_SIZE = (886, 1920)
SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")


def fail(message):
    raise ValueError(message)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command(arguments):
    return subprocess.run([str(x) for x in arguments], check=True, capture_output=True, text=True)


def probe(path):
    return json.loads(command(["ffprobe", "-v", "error", "-show_format", "-show_streams", "-of", "json", path]).stdout)


def load_assets(manifest_path):
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("version") != 1 or manifest.get("brand") != "Sofatap":
        fail("Manifest must have version 1 and brand Sofatap")
    result = {}
    for asset_id, item in manifest.get("assets", {}).items():
        if not SAFE_ID.fullmatch(asset_id):
            fail("Unsafe asset ID")
        path = Path(item["path"])
        if not path.is_absolute():
            path = manifest_path.parent / path
        if not path.is_file() or sha256(path) != item.get("sha256"):
            fail(f"Source file/hash mismatch: {asset_id}")
        required = ("capturedAt", "deviceModel", "osVersion", "appVersion", "appBuild", "uiLocale", "captureMethod")
        if not all(isinstance(item.get(key), str) and item[key].strip() for key in required):
            fail(f"Physical capture provenance is incomplete: {asset_id}")
        datetime.fromisoformat(item["capturedAt"].replace("Z", "+00:00"))
        review = item.get("publicReview")
        if item.get("physicalDevice") is not True or review not in ("approved", "approved-selected-trims") or item.get("containsCredentials") is not False:
            fail(f"Only reviewed physical-device captures without credentials are allowed: {asset_id}")
        if review == "approved-selected-trims" and item.get("kind") != "video":
            fail(f"Selected-trim review is only valid for captured video: {asset_id}")
        alterations = item.get("uiAlterations", "none")
        if alterations not in ("none", "privacy-redaction-only"):
            fail(f"Source UI may only have documented privacy redactions: {asset_id}")
        if item.get("kind") not in ("screenshot", "video"):
            fail(f"Unsupported source kind: {asset_id}")
        record = {**item, "path": path.resolve()}
        if item["kind"] == "screenshot":
            with Image.open(path) as image:
                image.verify()
            with Image.open(path) as image:
                record["dimensions"] = image.size
            if alterations == "privacy-redaction-only":
                original = item.get("originalCapture", {})
                original_path = Path(original.get("path", ""))
                if not original_path.is_absolute():
                    original_path = manifest_path.parent / original_path
                if not original_path.is_file() or sha256(original_path) != original.get("sha256"):
                    fail(f"Original privacy-redaction capture/hash missing: {asset_id}")
                with Image.open(original_path) as raw, Image.open(path) as prepared:
                    if raw.size != prepared.size:
                        fail(f"Privacy redaction changed source dimensions: {asset_id}")
                    difference = ImageChops.difference(raw.convert("RGB"), prepared.convert("RGB"))
                    redactions = item.get("privacyRedactions", [])
                    if not redactions or difference.getbbox() is None:
                        fail(f"Privacy redactions must identify actual changed rectangles: {asset_id}")
                    for redaction in redactions:
                        bounds = redaction.get("bounds", [])
                        if len(bounds) != 4 or not all(isinstance(n, int) for n in bounds):
                            fail(f"Invalid privacy rectangle: {asset_id}")
                        x, y, width, height = bounds
                        if x < 0 or y < 0 or width <= 0 or height <= 0 or x + width > raw.width or y + height > raw.height or redaction.get("reason") != "private-network-address" or redaction.get("method") != "gaussian-blur":
                            fail(f"Unsupported privacy redaction: {asset_id}")
                        difference.paste((0, 0, 0), (x, y, x + width, y + height))
                    if difference.getbbox() is not None:
                        fail(f"Pixels outside declared privacy rectangles changed: {asset_id}")
        else:
            if alterations != "none":
                fail(f"Video redaction requires separate verified production support: {asset_id}")
            metadata = probe(path)
            video = [s for s in metadata["streams"] if s["codec_type"] == "video"]
            if len(video) != 1:
                fail(f"Expected one real video stream: {asset_id}")
            record["probe"] = metadata
            record["dimensions"] = (video[0]["width"], video[0]["height"])
            record["duration"] = float(metadata["format"]["duration"])
            if record["duration"] <= 0 or Fraction(video[0]["avg_frame_rate"]) <= 0:
                fail(f"Invalid captured video duration/rate: {asset_id}")
            if review == "approved-selected-trims":
                ranges = item.get("approvedRanges", [])
                if not ranges or any(len(r) != 2 or not all(isinstance(n, (int, float)) for n in r) or r[0] < 0 or r[0] >= r[1] or r[1] > record["duration"] for r in ranges):
                    fail(f"Valid reviewed video ranges are required: {asset_id}")
        if record["dimensions"][0] >= record["dimensions"][1]:
            fail(f"This recipe requires full portrait captures: {asset_id}")
        result[asset_id] = record
    return manifest, result


def font_path(locale, bold=False, override=None):
    if override:
        paths = [Path(override)]
    elif locale.startswith(("zh", "ja")):
        paths = [Path("/System/Library/Fonts/Hiragino Sans GB.ttc"), Path("/System/Library/Fonts/Supplemental/Arial Unicode.ttf"), Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc")]
    else:
        paths = [Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf"), Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")]
    selected = next((p for p in paths if p.is_file()), None)
    if selected is None:
        fail("A font covering the requested language is required; provide --font")
    return selected


def wrap(draw, text, font, width):
    lines = []
    for paragraph in text.split("\n"):
        # Preserve natural word boundaries in Latin text and allow CJK line breaks.
        units = paragraph.split(" ") if " " in paragraph else list(paragraph)
        separator = " " if " " in paragraph else ""
        line = ""
        for unit in units:
            candidate = separator.join(filter(None, [line, unit]))
            if draw.textlength(candidate, font=font) > width and line:
                lines.append(line)
                line = unit
            else:
                line = candidate
        lines.append(line)
    return lines


def text_block(draw, text, x, y, width, max_height, size, color, font_file, max_lines=3):
    for point_size in range(size, max(18, size // 2) - 1, -1):
        font = ImageFont.truetype(str(font_file), point_size)
        lines = wrap(draw, text, font, width)
        line_height = math.ceil(point_size * 1.24)
        if len(lines) <= max_lines and len(lines) * line_height <= max_height and all(draw.textlength(line, font=font) <= width for line in lines):
            for index, line in enumerate(lines):
                draw.text((x, y + index * line_height), line, fill=color, font=font, anchor="lt")
            return {"fontSize": point_size, "lineCount": len(lines), "bounds": [x, y, width, len(lines) * line_height]}
    fail("Headline/caption does not fit; shorten the actual copy")


def localized(recipe, locale):
    copy = recipe.get("copy", {}).get(locale)
    if not copy or not isinstance(copy.get("headline"), str):
        fail(f"Missing reviewed copy for {locale}")
    return copy


def source_for(recipe, locale, assets, kind, allow_fallback):
    asset_id = recipe.get("sources", {}).get(locale)
    if asset_id is None or asset_id not in assets:
        fail(f"Missing source for {recipe['id']} / {locale}")
    asset = assets[asset_id]
    if asset["kind"] != kind:
        fail(f"{recipe['id']} requires real {kind} capture, not {asset['kind']}")
    if asset["uiLocale"] != locale and not allow_fallback:
        fail(f"UI language {asset['uiLocale']} does not match storefront {locale}; capture localized UI or explicitly allow fallback")
    if kind == "video" and asset["publicReview"] == "approved-selected-trims":
        start = source_start(recipe, locale)
        end = start + float(recipe["durationSeconds"])
        if not any(start >= a and end <= b for a, b in asset["approvedRanges"]):
            fail(f"Video trim extends beyond visually approved private-data-free ranges: {asset_id}")
    return asset_id, asset


def source_start(recipe, locale):
    value = recipe.get("startSeconds", 0)
    if isinstance(value, dict):
        if locale not in value:
            fail(f"Missing source trim start for {recipe['id']} / {locale}")
        value = value[locale]
    return float(value)


def source_public_record(asset_id, asset):
    # No local filesystem path, device UDID, LAN endpoint, or app credentials.
    keys = ("sha256", "kind", "capturedAt", "deviceModel", "osVersion", "appVersion", "appBuild", "uiLocale", "captureMethod", "physicalDevice", "publicReview", "containsCredentials")
    record = {"assetId": asset_id, **{key: asset[key] for key in keys}, "dimensions": list(asset["dimensions"]), "uiAlterations": asset.get("uiAlterations", "none")}
    if asset.get("uiAlterations") == "privacy-redaction-only":
        record["originalCaptureSHA256"] = asset["originalCapture"]["sha256"]
        record["privacyRedactions"] = asset["privacyRedactions"]
        record["outsideRedactionPixelsUnchanged"] = True
    if asset["publicReview"] == "approved-selected-trims":
        record["approvedRanges"] = asset["approvedRanges"]
        record["wholeOriginalPublishable"] = False
    return record


def frame_screenshot(asset, recipe, locale, size, target, font_override):
    width, height = size
    unit = width / 1320
    canvas = Image.new("RGB", size, BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    margin = round(84 * unit)
    copy = localized(recipe, locale)
    label_font = ImageFont.truetype(str(font_path(locale, override=font_override)), round(35 * unit))
    draw.text((margin, round(88 * unit)), "Sofatap", font=label_font, fill=MINT, anchor="lt")
    title = text_block(draw, copy["headline"], margin, round(160 * unit), width - margin * 2, round(300 * unit), round(104 * unit), FOREGROUND, font_path(locale, bold=True, override=font_override), max_lines=2)
    if copy.get("subhead"):
        text_block(draw, copy["subhead"], margin, round(442 * unit), width - margin * 2, round(148 * unit), round(40 * unit), MUTED, font_path(locale, override=font_override), max_lines=2)
    top = round(620 * unit)
    bottom = round(68 * unit)
    available = (width - margin * 2, height - top - bottom)
    with Image.open(asset["path"]) as original:
        original = original.convert("RGB")
        scale = min(available[0] / original.width, available[1] / original.height)
        fitted = (round(original.width * scale), round(original.height * scale))
        screen = original.resize(fitted, Image.Resampling.LANCZOS)
    left = (width - fitted[0]) // 2
    # Decorative border stays outside the full untouched source rectangle.
    draw.rounded_rectangle((left - 5, top - 5, left + fitted[0] + 5, top + fitted[1] + 5), radius=7, fill=(44, 68, 61))
    canvas.paste(screen, (left, top))
    canvas.save(target, format="PNG", optimize=True)
    with Image.open(target) as final:
        assert final.mode == "RGB" and final.size == size
    return {"sourceScale": scale, "sourcePlacement": [left, top, *fitted], "operation": "Full prepared source uniformly resized, uncropped, with separate headline canvas; privacy exceptions are recorded with the source", "titleLayout": title}


def preview_canvas(recipe, locale, target, font_override):
    canvas = Image.new("RGB", PREVIEW_SIZE, BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    copy = localized(recipe, locale)
    text_block(draw, copy["headline"], 42, 42, 802, 148, 53, FOREGROUND, font_path(locale, bold=True, override=font_override), max_lines=2)
    canvas.save(target, format="PNG")


def render_preview(recipes, locale, assets, destination, allow_fallback, font_override):
    segments = []
    sources = []
    total_frames = 0
    for index, recipe in enumerate(recipes):
        asset_id, asset = source_for(recipe, locale, assets, "video", allow_fallback)
        start = source_start(recipe, locale)
        duration = float(recipe["durationSeconds"])
        frames = round(duration * 30)
        if start < 0 or frames < 30 or abs(duration - frames / 30) > .001 or start + duration > asset["duration"] + .02:
            fail(f"Invalid real capture trim: {recipe['id']}")
        total_frames += frames
        canvas = destination / f"segment-{index:02d}-canvas.png"
        preview_canvas(recipe, locale, canvas, font_override)
        segment = destination / f"segment-{index:02d}.mp4"
        # A full source is uniformly fitted below a separate caption strip.
        # Source PTS are normalized, not sped up; fps duplicates/drops for CFR only.
        filters = "[0:v]setpts=PTS-STARTPTS,scale=886:1710:force_original_aspect_ratio=decrease:force_divisible_by=2,pad=886:1710:(ow-iw)/2:(oh-ih)/2:color=0x091114,setsar=1,fps=30[screen];[1:v][screen]overlay=x=0:y=210:shortest=1,format=yuv420p[v]"
        args = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-threads", "2", "-ss", str(start), "-t", str(duration), "-i", asset["path"], "-loop", "1", "-framerate", "30", "-i", canvas, "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-filter_complex_threads", "1", "-filter_complex", filters, "-map", "[v]", "-map", "2:a:0", "-frames:v", str(frames), "-t", str(duration), "-c:v", "libx264", "-threads", "2", "-preset", "medium", "-profile:v", "high", "-level:v", "4.0", "-b:v", "11M", "-minrate", "11M", "-maxrate", "11M", "-bufsize", "22M", "-x264-params", "nal-hrd=cbr:filler=1", "-g", "60", "-keyint_min", "60", "-sc_threshold", "0", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2", "-movflags", "+faststart", segment]
        command(args)
        segments.append(segment)
        sources.append({**source_public_record(asset_id, asset), "sceneId": recipe["id"], "sourceStartSeconds": start, "durationSeconds": duration, "playbackSpeed": 1, "sourceAudio": "muted; silent AAC track supplied", "uiLocaleFallback": asset["uiLocale"] != locale})
    duration = total_frames / 30
    if not 15 <= duration <= 30:
        fail("App Preview must be 15–30 seconds")
    concat = destination / "segments.ffconcat"
    # Generated segment names cannot contain quoting characters or user input.
    concat.write_text("ffconcat version 1.0\n" + "".join(f"file '{p.name}'\n" for p in segments))
    output = destination / f"Sofatap-App-Preview-{locale}.mp4"
    command(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "1", "-i", concat, "-c", "copy", "-movflags", "+faststart", output])
    metadata = probe(output)
    video = next(s for s in metadata["streams"] if s["codec_type"] == "video")
    audio = next(s for s in metadata["streams"] if s["codec_type"] == "audio")
    assert (video["width"], video["height"]) == PREVIEW_SIZE and video["codec_name"] == "h264" and video["level"] <= 40
    # iOS HEVC captures may carry full-range 4:2:0, named yuvj420p by ffprobe.
    # Preserve its range metadata instead of relabeling limited/full values.
    assert Fraction(video["avg_frame_rate"]) == 30 and video["pix_fmt"] in ("yuv420p", "yuvj420p")
    assert audio["codec_name"] == "aac" and audio["channels"] == 2 and int(audio["sample_rate"]) == 48000
    assert abs(float(metadata["format"]["duration"]) - duration) < .12 and output.stat().st_size < 500_000_000
    command(["ffmpeg", "-hide_banner", "-loglevel", "error", "-threads", "2", "-i", output, "-f", "null", "-"])
    poster = destination / f"Sofatap-App-Preview-{locale}-poster.png"
    command(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-ss", "5", "-i", output, "-frames:v", "1", poster])
    return {"file": output.name, "sha256": sha256(output), "bytes": output.stat().st_size, "durationSeconds": duration, "dimensions": list(PREVIEW_SIZE), "fps": 30, "codec": "H.264 High <= 4.0", "pixelFormat": video["pix_fmt"], "colorRange": video.get("color_range", "unspecified"), "videoBitrate": int(video.get("bit_rate", 0)), "audio": "silent AAC stereo, 48 kHz; encoding target 256 kbps", "sources": sources, "poster": {"file": poster.name, "sha256": sha256(poster), "timeSeconds": 5}, "fullDecodePassed": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--storyboard", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--locales", nargs="+", default=["en-US", "zh-Hans", "ja"])
    parser.add_argument("--mode", choices=["validate", "screenshots", "preview", "all"], default="validate")
    parser.add_argument("--allow-ui-locale-fallback", action="store_true")
    parser.add_argument("--font", type=Path)
    args = parser.parse_args()
    for executable in ("ffmpeg", "ffprobe"):
        if not shutil.which(executable):
            fail(f"Missing {executable}")
    _, assets = load_assets(args.manifest.resolve())
    story = json.loads(args.storyboard.read_text())
    if story.get("version") != 1:
        fail("Unsupported storyboard version")
    if not 5 <= len(story.get("screenshots", [])) <= 6:
        fail("This production plan expects five or six screenshots")
    for group in ("screenshots", "preview"):
        ids = [r["id"] for r in story.get(group, [])]
        if len(set(ids)) != len(ids) or any(not SAFE_ID.fullmatch(i) for i in ids):
            fail(f"Duplicate/unsafe recipe IDs in {group}")
    preview_duration = sum(float(x["durationSeconds"]) for x in story.get("preview", []))
    if not 15 <= preview_duration <= 30:
        fail("Preview storyboard duration must be 15–30 seconds")
    for locale in args.locales:
        if not SAFE_ID.fullmatch(locale):
            fail("Unsafe locale")
        for group, kind in (("screenshots", "screenshot"), ("preview", "video")):
            if args.mode not in ("all", "validate", group):
                continue
            for recipe in story[group]:
                localized(recipe, locale)
                source_for(recipe, locale, assets, kind, args.allow_ui_locale_fallback)
    if args.mode == "validate":
        print(json.dumps({"validated": True, "assets": len(assets), "locales": args.locales, "noOutputRendered": True}))
        return
    args.output.mkdir(parents=True, exist_ok=True)
    receipt = {"version": 1, "brand": "Sofatap", "createdAt": datetime.now(timezone.utc).isoformat(), "manifestSHA256": sha256(args.manifest), "storyboardSHA256": sha256(args.storyboard), "scriptSHA256": sha256(Path(__file__)), "sourceUIChanged": any(a.get("uiAlterations") == "privacy-redaction-only" for a in assets.values()), "allowedSourceUIChange": "Only verified, declared privacy redactions of private network addresses", "locales": {}}
    # Preserve exact recipe inputs privately, even when later locales update them.
    # package_gallery copies only final media; it never exports this directory.
    frozen = args.output / ".production-inputs"
    frozen.mkdir(exist_ok=True)
    for source, key, suffix in ((args.manifest, "manifestSHA256", ".json"), (args.storyboard, "storyboardSHA256", ".json"), (Path(__file__), "scriptSHA256", ".py")):
        target = frozen / (receipt[key] + suffix)
        if target.exists():
            if sha256(target) != receipt[key]:
                fail("Immutable recipe snapshot was changed")
        else:
            shutil.copyfile(source, target)
    for locale in args.locales:
        destination = args.output / locale
        destination.mkdir(exist_ok=True)
        results = {}
        if args.mode in ("all", "screenshots"):
            shots = []
            for index, recipe in enumerate(story["screenshots"], 1):
                asset_id, asset = source_for(recipe, locale, assets, "screenshot", args.allow_ui_locale_fallback)
                for size in SCREENSHOT_SIZES:
                    folder = destination / f"screenshots-{size[0]}x{size[1]}"
                    folder.mkdir(exist_ok=True)
                    target = folder / f"{index:02d}-{recipe['id']}.png"
                    layout = frame_screenshot(asset, recipe, locale, size, target, args.font)
                    shots.append({"file": str(target.relative_to(destination)), "sha256": sha256(target), "dimensions": list(size), "colorMode": "RGB", "source": source_public_record(asset_id, asset), "uiLocaleFallback": asset["uiLocale"] != locale, **layout})
            results["screenshots"] = shots
        if args.mode in ("all", "preview"):
            folder = destination / "preview"
            folder.mkdir(exist_ok=True)
            results["preview"] = render_preview(story["preview"], locale, assets, folder, args.allow_ui_locale_fallback, args.font)
        receipt["locales"][locale] = results
    target = args.output / f"production-manifest-{args.mode}.json"
    target.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "receipt": str(target), "locales": args.locales}))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, AssertionError, subprocess.CalledProcessError) as error:
        print(f"Production stopped: {error}", file=sys.stderr)
        raise SystemExit(1)
