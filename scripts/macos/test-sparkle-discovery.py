#!/usr/bin/env python3
"""Offline Sparkle integration checks using an ephemeral in-memory test key.

Runs only a test bundle with a noninteractive driver. No production app process,
production Keychain access, remote network, update-archive download, or installation occurs. A loopback-only
HTTP server supplies synthetic feed bytes to Sparkle.
"""
import contextlib
import http.server
import threading
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

from sparkle import CONFIG, fetch

root = CONFIG.parents[2]
config = json.loads(CONFIG.read_text())
# Dependency fetching is a separate build step; do not network in this test.
dependency = root / '.tools' / ('Sparkle-' + config['sparkleVersion'])
if not (dependency / 'SOFATAP-DEPENDENCY.json').exists():
    raise SystemExit('First fetch the pinned dependency with scripts/macos/sparkle.py fetch .tools/Sparkle-2.10.0')
fetch(dependency)  # Validates existing cached bytes, no download.
with contextlib.ExitStack() as cleanup, tempfile.TemporaryDirectory(prefix='sofatap-discovery-') as temporary:
    stage = Path(temporary)
    probe = stage / 'Probe'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-F', str(dependency),
                    '-framework', 'Sparkle', '-Xlinker', '-rpath', '-Xlinker', str(dependency),
                    str(root / 'desktop/macos/ReceiverUpdatePolicy.swift'),
                    str(root / 'desktop/macos/tests/SparkleDiscoveryProbe.swift'), '-o', str(probe)], check=True)
    key_source = stage / 'key.swift'
    key_source.write_text('''import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
let output = ["seed": key.rawRepresentation.base64EncodedString(), "public": key.publicKey.rawRepresentation.base64EncodedString()]
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output))
''')
    # Test seed is captured in memory and piped directly to the signing tool.
    # Never print, persist, or use the production signing key in this test.
    key = json.loads(subprocess.check_output(['xcrun', 'swift', str(key_source)]))
    feed = stage / 'appcast.xml'
    def signed_items(items):
        def item_xml(version, channel):
            channel_xml = '<sparkle:channel>' + channel + '</sparkle:channel>' if channel else ''
            return ('<item><title>Fixture update</title><sparkle:version>' + str(version)
                + '</sparkle:version><sparkle:shortVersionString>99.0</sparkle:shortVersionString>'
                + channel_xml + '<sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>'
                + '<enclosure url="https://example.invalid/never-download.zip" length="10" '
                + 'type="application/octet-stream" sparkle:edSignature="'
                + 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=='
                + '"/></item>')
        feed.write_text('<?xml version="1.0" encoding="utf-8"?><rss version="2.0" '
            + 'xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
            + '<channel><title>Offline test</title>'
            + ''.join(item_xml(version, channel) for version, channel in items)
            + '</channel></rss>')
        subprocess.run([str(dependency / 'bin/sign_update'), '--ed-key-file', '-', str(feed)],
                        input=key['seed'].encode(), check=True, capture_output=True)
        return feed.read_bytes()

    signed_feed = signed_items([(99999, '')])
    requests = []
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            if self.path.split('?')[0] != '/appcast.xml':
                self.send_error(404)
                return
            body = feed.read_bytes()
            self.send_response(200)
            self.send_header('Content-Type', 'application/rss+xml')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def log_message(self, *args): pass
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    cleanup.callback(server.server_close)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    cleanup.callback(server.shutdown)
    feed_url = 'http://127.0.0.1:' + str(server.server_port) + '/appcast.xml'

    def discover(current_version, release_version="0.8.0"):
        app = stage / ('Probe-' + uuid.uuid4().hex + '.app')
        (app / 'Contents/MacOS').mkdir(parents=True)
        shutil.copyfile('/usr/bin/true', app / 'Contents/MacOS/Probe')
        (app / 'Contents/MacOS/Probe').chmod(0o755)
        info = {'CFBundleIdentifier': 'com.chekusu.sofatap.update-probe.' + uuid.uuid4().hex,
            'CFBundleExecutable': 'Probe', 'CFBundleName': 'Offline update probe', 'CFBundlePackageType': 'APPL',
            'CFBundleVersion': current_version, 'CFBundleShortVersionString': '0.0.1', 'SUFeedURL': feed_url,
            'SofatapReleaseVersion': release_version,
            'SUPublicEDKey': key['public'], 'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True,
            'SUSignedFeedFailureExpirationInterval': 0, 'SUEnableAutomaticChecks': False,
            'SUAutomaticallyUpdate': False, 'SUEnableSystemProfiling': False}
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
        result = subprocess.run([str(probe), str(app)], capture_output=True, text=True, timeout=40)
        if result.returncode:
            raise RuntimeError(result.stderr)
        return json.loads(result.stdout)

    newer = discover('1')
    assert newer['foundVersion'] == '99999', newer
    current = discover('99999')
    assert current['foundVersion'] is None, current
    feed.write_bytes(signed_feed.replace(b'Fixture update', b'Tampered update'))
    invalid = discover('1')
    assert invalid['foundVersion'] is None and invalid['errorCode'] is not None, invalid
    # Both clients see the same signed feed. Stable must choose the lower stable
    # item rather than the higher beta; beta must choose the newer beta item.
    signed_items([(99999, 'beta'), (99998, '')])
    stable_ignores_beta = discover('1', '0.8.0')
    assert stable_ignores_beta['foundVersion'] == '99998', stable_ignores_beta
    beta_accepts_beta = discover('1', '0.8.0-beta.1')
    assert beta_accepts_beta['foundVersion'] == '99999', beta_accepts_beta
    signed_items([(99999, 'beta')])
    stable_beta_only = discover('1', '0.8.0')
    assert stable_beta_only['foundVersion'] is None, stable_beta_only
    signed_items([(99999, '')])
    beta_accepts_stable = discover('1', '0.8.0-beta.1')
    assert beta_accepts_stable['foundVersion'] == '99999', beta_accepts_stable
    assert all(path.split('?')[0] == '/appcast.xml' for path in requests), requests
    print(json.dumps({'newer': newer, 'current': current, 'tampered': invalid,
                      'stableIgnoresHigherBeta': stable_ignores_beta, 'betaAcceptsBeta': beta_accepts_beta,
                      'stableExcludesBetaOnly': stable_beta_only, 'betaAcceptsStable': beta_accepts_stable,
                      'productionKeychainAccess': False, 'remoteNetwork': False, 'installation': False}, indent=2))
