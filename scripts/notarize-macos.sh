#!/bin/bash
# Preflight by default. Only --submit creates an Apple notarization submission.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 - "$repo_dir" "$@" <<'PY'
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time

TEAM = "FKSR2JD63B"
IDENTITY = f"Developer ID Application: CHEKUSU INC. ({TEAM})"
BUNDLE = "com.chekusu.sofatap.receiver"
ROOT = Path(sys.argv[1]).resolve()
parser = argparse.ArgumentParser(description="Preflight, submit, or resume notarization of a clean CHEKUSU macOS build.")
parser.add_argument("--app", required=True, type=Path, help="Signed Sofa Tap Receiver.app from build-macos.sh")
parser.add_argument("--manifest", required=True, type=Path, help="That build's BUILD-MANIFEST.json")
parser.add_argument("--output-dir", required=True, type=Path, help="New directory, outside the source tree or Git-ignored")
parser.add_argument("--profile", help="Existing ASC Keychain profile; omitted uses its current default")
mode = parser.add_mutually_exclusive_group()
mode.add_argument("--submit", action="store_true", help="Upload a new submission, wait, staple and assess")
mode.add_argument("--resume", action="store_true", help="Resume the submission recorded in output-dir without uploading again")
parser.add_argument("--timeout", type=int, default=1800, help="Status polling time limit in seconds (default: 1800)")
parser.add_argument("--poll-interval", type=int, default=15, help="Seconds between Apple status checks (default: 15)")
args = parser.parse_args(sys.argv[2:])
receipt = None
receipt_path = None


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def now():
    return datetime.now(timezone.utc).isoformat()


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else hash_stream(stream)


def hash_stream(stream):
    digest = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(block)
    return digest.hexdigest()


def run(command, *, timeout=120, sensitive=False):
    try:
        result = subprocess.run(command, cwd=ROOT, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"{Path(command[0]).name} timed out; do not repeat an uncertain submission.") from error
    if result.returncode:
        # ASC can include upload URLs in diagnostics. Do not persist its raw output.
        detail = "" if sensitive else ": " + result.stderr.decode("utf-8", errors="replace")[-4000:].strip()
        raise RuntimeError(f"{Path(command[0]).name} failed (exit {result.returncode}){detail}")
    return result


def asc_json(*command, timeout=120):
    result = run([asc, "--profile", profile, *command, "--output", "json"], timeout=timeout, sensitive=True)
    try:
        return json.loads(result.stdout)
    except (ValueError, UnicodeDecodeError) as error:
        raise RuntimeError("ASC returned invalid JSON; inspect notarization history before retrying a submission.") from error


def save_receipt(stage, **fields):
    receipt.update(fields)
    receipt["stage"] = stage
    receipt["updatedAt"] = now()
    temporary = receipt_path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, receipt_path)


def clean_revision():
    revision = run(["git", "rev-parse", "HEAD"]).stdout.decode().strip()
    require(not run(["git", "status", "--porcelain", "--untracked-files=all"]).stdout.strip(),
            "Source tree is dirty. Commit the intended changes, then rebuild before notarizing.")
    return revision


def check_signature(path, expected_identifier):
    result = run(["codesign", "--display", "--verbose=4", str(path)])
    details = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    fields = {}
    for line in details.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            fields.setdefault(key, []).append(value)
    require("Signature=adhoc" not in details, f"Ad-hoc signing is not accepted: {path.name}")
    require(IDENTITY in fields.get("Authority", []), f"Expected CHEKUSU Developer ID Application signing: {path.name}")
    require(fields.get("TeamIdentifier") == [TEAM], f"Unexpected signing team: {path.name}")
    require(fields.get("Identifier") == [expected_identifier], f"Unexpected signed identifier: {path.name}")
    # The numeric CodeDirectory flags are authoritative; runtime is bit 0x10000.
    flags = re.search(r"\bflags=(0x[0-9a-fA-F]+)\b", details)
    require(flags is not None and int(flags.group(1), 16) & 0x10000,
            f"Hardened runtime is missing: {path.name}")
    timestamp = fields.get("Timestamp", [])
    require(len(timestamp) == 1 and timestamp[0].strip() and timestamp[0].lower() != "none",
            f"Secure signing timestamp is missing: {path.name}")
    entitlement_result = run(["codesign", "--display", "--entitlements", ":-", str(path)])
    entitlement_data = entitlement_result.stdout.strip()
    entitlements = plistlib.loads(entitlement_data) if entitlement_data else {}
    require(isinstance(entitlements, dict), f"Malformed entitlements: {path.name}")
    require(not entitlements.get("com.apple.security.get-task-allow", False),
            f"Development get-task-allow entitlement is enabled: {path.name}")
    return {"identifier": expected_identifier, "team": TEAM, "authority": IDENTITY,
            "hardenedRuntime": True, "timestamp": timestamp[0],
            "cdhash": fields.get("CDHash", [None])[0], "entitlements": entitlements}


def verify_app(app, manifest):
    require(app.is_dir() and app.suffix == ".app", "--app must be an existing .app bundle.")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == BUNDLE and info.get("CFBundleExecutable") == "SofaTap",
            "The app's Info.plist is not the Sofa Tap receiver bundle.")
    paths = {"executable": app / "Contents/MacOS/SofaTap", "backend": app / "Contents/Helpers/SofaTapHost"}
    for name, path in paths.items():
        require(path.is_file() and not path.is_symlink(), f"Missing regular {name} executable.")
        require(manifest.get(name + "SHA256") == sha256(path),
                f"The signed {name} hash differs from BUILD-MANIFEST.json; rebuild using the Developer ID identity.")
    # Reject new executable code until this pipeline's signing and manifest checks cover it.
    macho_magic = {bytes.fromhex(value) for value in ("feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}
    known = set(paths.values())
    for item in app.rglob("*"):
        require(not item.is_symlink(), "Unexpected symlink in the receiver bundle; review the packaging before submitting.")
        if item.is_file():
            with item.open("rb") as stream:
                is_macho = stream.read(4) in macho_magic
            require(not is_macho or item in known, f"Unreviewed native code in app: {item.relative_to(app)}")
    run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)])
    signatures = {
        "app": check_signature(app, BUNDLE),
        "executable": check_signature(paths["executable"], BUNDLE),
        "backend": check_signature(paths["backend"], BUNDLE + ".host"),
    }
    require(signatures["backend"]["entitlements"].get("com.apple.security.cs.allow-jit") is True,
            "The .NET backend is missing its required allow-jit entitlement.")
    return signatures


def submission_fields(response):
    data = response.get("data", {})
    attributes = data.get("attributes", {})
    submission_id = data.get("id")
    require(isinstance(submission_id, str) and re.fullmatch(r"[0-9a-fA-F-]{36}", submission_id),
            "ASC did not return a valid submission ID. Inspect notarization history before trying a new submission.")
    status = attributes.get("status")
    require(isinstance(status, str) and status, "ASC did not return a submission status.")
    return submission_id, status


try:
    require(sys.platform == "darwin", "Run on macOS with Xcode Command Line Tools installed.")
    require(args.timeout > 0 and args.poll_interval > 0, "Timeout and polling interval must be positive seconds.")
    for utility in ("asc", "codesign", "ditto", "xcrun", "spctl", "git"):
        require(shutil.which(utility), f"Required utility is missing: {utility}")
    asc = shutil.which("asc")
    require(not args.app.is_symlink() and not args.manifest.is_symlink(), "App and manifest must not be symlinks.")
    app = args.app.resolve()
    manifest_path = args.manifest.resolve()
    output = args.output_dir.resolve()
    require(output != app and app not in output.parents, "Output directory cannot be inside the input app.")
    require(output != ROOT, "Output directory cannot be the repository root.")
    if ROOT in output.parents:
        ignored = subprocess.run(["git", "check-ignore", "--quiet", str(output / "NOTARIZATION-RECEIPT.json")], cwd=ROOT)
        require(ignored.returncode == 0, "Output inside the repository must be Git-ignored (for example artifacts/notarization/...).")
    revision = clean_revision()
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    require(manifest.get("sourceDirty") is False, "The build manifest marks a dirty or unspecified source tree; rebuild from clean source.")
    require(manifest.get("sourceRevision") == revision, "Build manifest source revision must equal the current clean HEAD.")
    require(manifest.get("bundleIdentifier") == BUNDLE, "Unexpected bundle identifier in build manifest.")
    require(manifest.get("signature") == IDENTITY and manifest.get("hardenedRuntime") is True,
            "Build manifest must describe a Developer ID build with hardened runtime.")
    require(manifest.get("runtime") in ("osx-arm64", "osx-x64"), "Unexpected build runtime in manifest.")
    signatures = verify_app(app, manifest)
    # Resolve a stored profile once, then pass it explicitly to every ASC command.
    auth_command = [asc] + (["--profile", args.profile] if args.profile else [])
    auth = json.loads(run([*auth_command, "auth", "status", "--output", "json"], sensitive=True).stdout)
    require(auth.get("environmentCredentialsProvided") is False, "ASC environment credentials are present; use only the existing Keychain profile.")
    profiles = [entry for entry in auth.get("credentials", [])
                if entry.get("name") == args.profile] if args.profile else [entry for entry in auth.get("credentials", []) if entry.get("isDefault")]
    require(len(profiles) == 1 and profiles[0].get("storedIn") == "keychain", "An unambiguous ASC Keychain profile is required.")
    profile = profiles[0]["name"]
    report = {"schemaVersion": 1, "stage": "preflight-passed", "createdAt": now(),
              "sourceRevision": revision, "sourceDirty": False, "runtime": manifest["runtime"],
              "bundleIdentifier": BUNDLE, "manifestSHA256": sha256(manifest_path),
              "executableSHA256": manifest["executableSHA256"], "backendSHA256": manifest["backendSHA256"],
              "signatures": signatures, "ascExecutable": asc, "authStorage": "System Keychain", "authProfile": profile,
              "notarized": False, "stapled": False, "gatekeeperAccepted": False}
    if not args.submit and not args.resume:
        require(not output.exists(), "Choose a new output directory; --resume is for an existing recorded submission.")
        print(json.dumps(report, indent=2))
        print("Preflight passed. Nothing uploaded or modified. Add --submit to create a notarization submission.", file=sys.stderr)
        sys.exit(0)

    if args.resume:
        receipt_path = output / "NOTARIZATION-RECEIPT.json"
        existing_receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        for field in ("sourceRevision", "runtime", "manifestSHA256", "executableSHA256", "backendSHA256", "authProfile"):
            require(existing_receipt.get(field) == report[field], f"Resume differs from recorded {field}; use the original build and profile.")
        submission_id = existing_receipt.get("submissionID")
        require(isinstance(submission_id, str) and re.fullmatch(r"[0-9a-fA-F-]{36}", submission_id),
                "No confirmed submission ID was recorded. Inspect ASC history before starting another submission; do not blindly retry.")
        require(existing_receipt.get("stage") != "complete", "This receipt already records a completed release; verify the existing final ZIP hash.")
        submission_zip = output / "submission.zip"
        require(submission_zip.is_file() and sha256(submission_zip) == existing_receipt.get("submissionZIP_SHA256"),
                "The recorded submission archive is missing or changed.")
        receipt = existing_receipt
    else:
        require(not output.exists(), "Output directory already exists. Use --resume for its recorded submission, or choose a new directory.")
        output.mkdir(parents=True)
        receipt_path = output / "NOTARIZATION-RECEIPT.json"
        receipt = report
        shutil.copyfile(manifest_path, output / "SOURCE-BUILD-MANIFEST.json")
        save_receipt("prepared")

    # Work outside File Provider folders. Stapling never modifies the input bundle.
    with tempfile.TemporaryDirectory(prefix="sofatap-notarize-") as temporary:
        working_app = Path(temporary) / app.name
        run(["ditto", str(app), str(working_app)])
        verify_app(working_app, manifest)
        if args.submit:
            submission_zip = output / "submission.zip"
            run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(working_app), str(submission_zip)])
            require(clean_revision() == revision, "HEAD changed after preflight. Rebuild and inspect the new revision before submitting.")
            save_receipt("submitting", submissionZIP_SHA256=sha256(submission_zip), submissionOutcome="unknown")
            print("Uploading one notarization submission using the existing ASC Keychain profile...", flush=True)
            response = asc_json("notarization", "submit", "--file", str(submission_zip), timeout=args.timeout)
            submission_id, status = submission_fields(response)
            save_receipt("submitted", submissionID=submission_id, appleStatus=status, submissionOutcome="confirmed")
            print(f"Submission ID: {submission_id}", flush=True)

        deadline = time.monotonic() + args.timeout
        while True:
            remaining = deadline - time.monotonic()
            require(remaining > 0, "Apple status wait timed out. Resume this output directory; do not submit again.")
            response = asc_json("notarization", "status", "--id", submission_id, timeout=min(120, remaining))
            returned_id, status = submission_fields(response)
            require(returned_id == submission_id, "Apple status response returned a different submission ID.")
            save_receipt("waiting", appleStatus=status)
            print(f"Apple status: {status}", flush=True)
            if status == "Accepted":
                save_receipt("accepted", notarized=True, acceptedAt=now())
                break
            require(status not in ("Invalid", "Rejected"),
                    f"Apple returned {status}. Review asc notarization log --id {submission_id}; fix the build before another submission.")
            require(status == "In Progress", "Unknown Apple status; refusing to assume acceptance. Resume after inspection.")
            time.sleep(min(args.poll_interval, max(0, deadline - time.monotonic())))

        for stage, command, log_name in (
            ("stapled", ["xcrun", "stapler", "staple", str(working_app)], "staple.txt"),
            ("staple-validated", ["xcrun", "stapler", "validate", str(working_app)], "staple-validation.txt"),
            ("gatekeeper-accepted", ["spctl", "--assess", "--type", "execute", "--verbose=2", str(working_app)], "gatekeeper.txt"),
        ):
            result = run(command)
            (output / log_name).write_bytes(result.stdout + result.stderr)
            fields = {"stapled": True} if stage == "staple-validated" else {"gatekeeperAccepted": True} if stage == "gatekeeper-accepted" else {}
            save_receipt(stage, **fields)
        verify_app(working_app, manifest)
        final_name = f"SofaTap-macOS-{manifest['runtime'].removeprefix('osx-')}-notarized.zip"
        final_zip = output / final_name
        run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(working_app), str(final_zip)])
        final_hash = sha256(final_zip)
        (output / (final_name + ".sha256")).write_text(f"{final_hash}  {final_name}\n", encoding="utf-8")
        save_receipt("complete", completedAt=now(), finalArchive=final_name, finalZIP_SHA256=final_hash)
        print(f"Complete: {final_zip}\nReceipt: {receipt_path}")
except (Exception, KeyboardInterrupt) as error:
    message = str(error) or "Interrupted. Inspect the receipt before resuming; do not blindly repeat a submission."
    if receipt is not None and receipt_path is not None:
        try:
            previous = receipt.get("stage")
            save_receipt("failed", failedAfter=previous, error=message)
        except OSError:
            pass
    print(f"Notarization stopped: {message}", file=sys.stderr)
    sys.exit(1)
PY
