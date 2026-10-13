#!/bin/bash
# Real TLS/WebSocket transport against ephemeral 127.0.0.1 fixtures only.
set -euo pipefail
umask 077
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
TV_TRANSPORT_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/sofatap-tv-transport.XXXXXX")"
TV_FIXTURE_PID=""
cleanup() {
    if [[ -n "$TV_FIXTURE_PID" ]]; then
        kill "$TV_FIXTURE_PID" 2>/dev/null || true
        wait "$TV_FIXTURE_PID" 2>/dev/null || true
    fi
    rm -rf "$TV_TRANSPORT_STAGE"
}
trap cleanup EXIT
python3 -c 'import websockets.asyncio.server' || {
    echo 'Python websockets with asyncio.server is required.' >&2
    exit 1
}
for TV_CERT_NAME in control pointer; do
    openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 \
        -subj "/CN=sofatap-loopback-${TV_CERT_NAME}" \
        -keyout "$TV_TRANSPORT_STAGE/${TV_CERT_NAME}.key" \
        -out "$TV_TRANSPORT_STAGE/${TV_CERT_NAME}.pem" \
        >"$TV_TRANSPORT_STAGE/openssl-${TV_CERT_NAME}.log" 2>&1
done
python3 "$REPO_ROOT/tests/webos_transport_fixture.py" "$TV_TRANSPORT_STAGE" \
    >"$TV_TRANSPORT_STAGE/fixture.log" 2>&1 &
TV_FIXTURE_PID=$!
for ((TV_READY_TRY=0; TV_READY_TRY<100; TV_READY_TRY++)); do
    [[ -f "$TV_TRANSPORT_STAGE/fixture.json" ]] && break
    if ! kill -0 "$TV_FIXTURE_PID" 2>/dev/null; then
        cat "$TV_TRANSPORT_STAGE/fixture.log" >&2
        exit 1
    fi
    sleep 0.1
done
if [[ ! -f "$TV_TRANSPORT_STAGE/fixture.json" ]]; then
    echo 'Loopback fixture did not become ready.' >&2
    exit 1
fi
xcrun --sdk macosx swiftc -parse-as-library -swift-version 5 \
    -target "$(uname -m)-apple-macosx14.0" \
    "$REPO_ROOT/ios/SofaTap/Core/TV/WebOSTVSocket.swift" \
    "$REPO_ROOT/tests/WebOSTVTransportTests.swift" \
    -o "$TV_TRANSPORT_STAGE/tv-transport-tests"
"$TV_TRANSPORT_STAGE/tv-transport-tests" "$TV_TRANSPORT_STAGE"
