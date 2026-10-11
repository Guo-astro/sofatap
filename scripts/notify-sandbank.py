#!/usr/bin/env python3
"""Notify Sandbank Dev only after confirming a commit is published on GitHub."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

REPOSITORY = "https://github.com/chekusu/sofatap"
ORIGIN_URLS = {REPOSITORY, REPOSITORY + ".git", "git@github.com:chekusu/sofatap.git"}


def run(*args, cwd=None, timeout=60):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def git(root, *args):
    result = run("git", *args, cwd=root)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Git command failed")
    return result.stdout.strip()


def check_origin(root):
    # Read raw configuration so diagnostics never print an authenticated URL.
    fetch_urls = git(root, "config", "--get-all", "remote.origin.url").splitlines()
    push_result = run("git", "config", "--get-all", "remote.origin.pushurl", cwd=root)
    if push_result.returncode not in (0, 1):
        raise RuntimeError("Cannot read origin push URL")
    push_urls = push_result.stdout.strip().splitlines() or fetch_urls
    if len(fetch_urls) != 1 or len(push_urls) != 1 or any(
        url not in ORIGIN_URLS for url in fetch_urls + push_urls
    ):
        raise RuntimeError("origin fetch and push URLs must identify chekusu/sofatap on GitHub")


def check_ref(root, ref):
    if not ref.startswith("refs/heads/"):
        raise RuntimeError("Only an explicit branch ref is supported")
    git(root, "check-ref-format", ref)


def check_published(root, ref, sha):
    check_ref(root, ref)
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", sha):
        raise RuntimeError("Expected a full Git commit SHA")
    rows = git(root, "ls-remote", "--exit-code", "origin", ref).splitlines()
    if [row.split() for row in rows] != [[sha, ref]]:
        raise RuntimeError(f"origin {ref} does not point to {sha}; nothing was sent")


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def save_receipt(path, receipt):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix=".receipt-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            json.dump(receipt, output, ensure_ascii=False, indent=2)
            output.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def yobiru_command():
    configured = os.environ.get("YOBIRU_CLI")
    path = Path(configured).expanduser() if configured else None
    if configured and not path.is_file():
        resolved = shutil.which(configured)
        path = Path(resolved) if resolved else None
    if not configured:
        installed = shutil.which("yobiru")
        if installed:
            path = Path(installed)
        else:
            codex_home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
            filename = "yobiru.py" if os.name == "nt" else "yobiru"
            candidates = list((codex_home / "plugins/cache/yobiru/yobiru").glob("*/scripts/" + filename))
            path = max(candidates, key=lambda item: item.stat().st_mtime) if candidates else None
    if path is None or not path.is_file():
        raise RuntimeError("Yobiru CLI was not found; set YOBIRU_CLI to its installed script")
    if path.suffix == ".py":
        command = [sys.executable, str(path)]
    elif os.name == "nt":
        command = [str(path)]
    else:
        command = ["sh", str(path)]
    if os.environ.get("YOBIRU_HOME"):
        command += ["--home", os.environ["YOBIRU_HOME"]]
    return command


def message(receipt):
    return (
        "Sofa Tap published code synchronization request.\n"
        f"Repository: {REPOSITORY}\n"
        f"Branch/ref: {receipt['ref']}\n"
        f"Full commit SHA: {receipt['sha']}\n"
        f"Request key: {receipt['request_key']}\n\n"
        "The user has authorized keeping the Sandbank Dev checkout synchronized after each published change. "
        "Verify that origin is this GitHub repository, fetch the named branch, and confirm its full SHA. "
        "In the existing checkout, use fast-forward-only synchronization (git merge --ff-only or git pull --ff-only). "
        "If the checkout has uncommitted/untracked work, is on a different branch, has diverged, or origin no longer "
        "points to this SHA, stop and report the condition. Do not reset, clean, force checkout, stash, or overwrite work. "
        "Treat a repeated request key as the same synchronization request. "
        "Reply through Yobiru to this message with the resulting full HEAD SHA and checks or blockers. "
        "Message delivery alone is not confirmation that synchronization is complete."
    )


def deliver(root, path, receipt):
    receipt["attempts"] = receipt.get("attempts", 0) + 1
    receipt["last_attempt"] = timestamp()
    save_receipt(path, receipt)
    try:
        if receipt.get("repository") != REPOSITORY:
            raise RuntimeError("Receipt repository does not match Sofa Tap")
        target = receipt["target"]
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.:-]*(?:/[A-Za-z0-9_.-]+)?", target):
            raise RuntimeError("Invalid Yobiru target")
        # A retry checks GitHub again; it cannot announce an unpublished or outdated ref.
        check_published(root, receipt["ref"], receipt["sha"])
        result = run(*yobiru_command(), "send", target, message(receipt), "--kind", "request", "--wake", "now")
        try:
            response = json.loads(result.stdout)
        except json.JSONDecodeError:
            response = {}
        if not isinstance(response, dict):
            response = {}
        status, message_id = response.get("status"), response.get("id")
        if result.returncode or status not in (200, 202) or not isinstance(message_id, str) or not message_id:
            detail = result.stderr.strip() or result.stdout.strip() or "No delivery receipt"
            if status == 403 or "403" in detail:
                detail += "\nThe allowlist is unchanged. Report this policy block to the user."
            raise RuntimeError(detail)
        receipt.update(state="delivered", status=status, message_id=message_id, delivered_at=timestamp())
        receipt.pop("last_error", None)
        save_receipt(path, receipt)
        print(f"Yobiru HTTP {status}; message {message_id}; target {target}")
        print("Delivered only. Wait for an authenticated reply with matching reply_to before claiming synchronization.")
        print(f"Receipt: {path}")
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        receipt.update(state="pending", last_error=str(error))
        save_receipt(path, receipt)
        raise RuntimeError(f"{error}\nPending receipt: {path}\nRetry: python3 scripts/notify-sandbank.py --retry") from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--push", action="store_true", help="push the current clean branch first")
    parser.add_argument("--branch", help="expected current branch (defaults to the current branch)")
    parser.add_argument("--target", default=os.environ.get("SOFATAP_SYNC_TARGET", "sandbank-dev"), help="Sandbank Dev host[/agent]")
    parser.add_argument("--retry", action="store_true", help="retry all pending receipts after rechecking origin")
    args = parser.parse_args()
    if args.retry and (args.push or args.branch):
        parser.error("--retry cannot be combined with --push or --branch")
    root = Path(git(None, "rev-parse", "--show-toplevel"))
    check_origin(root)
    receipts = Path(git(root, "rev-parse", "--absolute-git-dir")) / "sofatap-sync"
    if args.retry:
        failed = False
        for path in sorted(receipts.glob("*.json")):
            receipt = json.loads(path.read_text(encoding="utf-8"))
            if receipt.get("state") == "pending":
                try:
                    deliver(root, path, receipt)
                except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                    print(f"{path}: {error}", file=sys.stderr)
                    failed = True
        return int(failed)
    if git(root, "status", "--porcelain", "--untracked-files=all"):
        raise RuntimeError("Commit or resolve tracked and untracked changes before publishing or notifying")
    branch = git(root, "symbolic-ref", "--quiet", "--short", "HEAD")
    if args.branch and args.branch != branch:
        raise RuntimeError("--branch must match the checked-out branch")
    ref = "refs/heads/" + branch
    check_ref(root, ref)
    sha = git(root, "rev-parse", "--verify", "HEAD^{commit}")
    if args.push:
        result = run("git", "push", "--", "origin", f"{sha}:{ref}", cwd=root, timeout=300)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or "git push failed; nothing was sent")
    request_key = hashlib.sha256(f"{REPOSITORY}\n{ref}\n{sha}\n{args.target}".encode()).hexdigest()
    path = receipts / (request_key + ".json")
    if path.exists():
        receipt = json.loads(path.read_text(encoding="utf-8"))
        if receipt.get("state") == "delivered":
            print(f"Already delivered as {receipt['message_id']}; remote synchronization still requires its reply.")
            return 0
    else:
        receipt = dict(repository=REPOSITORY, ref=ref, sha=sha, target=args.target,
                       request_key=request_key, state="pending", created_at=timestamp(), attempts=0)
    save_receipt(path, receipt)
    deliver(root, path, receipt)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired, ValueError, KeyError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
