#!/usr/bin/env python3
"""Exercise the Windows license assembly step with SDK and NuGet host fixtures.

No application execution, real package downloads or host-cache modifications.
"""
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "scripts/build-windows.sh").read_text()
LICENSE_STEP = SOURCE.split('python3 - "$repo_dir" "$release_dir" "$build_dir" <<\'PY\'\n', 1)[1].split("\nPY\n", 1)[0]
HOST = "microsoft.netcore.app.host.win-x64"
VERSION = "10.0.12"
BINARIES = {"apphost.exe": b"fixture-apphost", "singlefilehost.exe": b"fixture-singlefilehost"}


def check(mode, expected_error=None):
    with tempfile.TemporaryDirectory(prefix="sofatap-packaging-") as directory:
        root = Path(directory)
        cache, build, release = (root / part for part in ("cache", "build", "release"))
        build.mkdir()
        release.mkdir()
        libraries = {}
        names = ["microsoft.netcore.app.runtime.win-x64", "microsoft.aspnetcore.app.runtime.win-x64",
                 "microsoft.windowsdesktop.app.runtime.win-x64", "qrcoder"]
        for name in names:
            version = "1.7.0" if name == "qrcoder" else VERSION
            package = cache / name / version
            package.mkdir(parents=True)
            (package / "LICENSE.TXT").write_text("Fixture license\n")
            libraries[name + "/" + version] = {"type": "package"}
        if mode == "nuget":
            host = cache / HOST / VERSION
            libraries[HOST + "/" + VERSION] = {"type": "package"}
        else:
            host = root / "sdk/packs/Microsoft.NETCore.App.Host.win-x64" / VERSION
        (host / "runtimes/win-x64/native").mkdir(parents=True)
        for name, data in BINARIES.items():
            (host / "runtimes/win-x64/native" / name).write_bytes(data)
        if mode == "nuget":
            (host / "LICENSE.TXT").write_text("Fixture host license\n")
        for component, project in (("backend", "SofaTap.Host"), ("frontend", "SofaTap.Desktop")):
            assets = build / (component + "-intermediate/obj") / project / "project.assets.json"
            assets.parent.mkdir(parents=True)
            assets.write_text(json.dumps({"packageFolders": {str(cache): {}}, "libraries": libraries,
                                          "project": {"frameworks": {"net10.0": {}}}}))
            metadata = {"RuntimeIdentifier": "win-x64", "NuGetPackageVersion": VERSION,
                        "NuGetPackageId": "Microsoft.NETCore.App.Host.win-x64", "PackageDirectory": str(host),
                        "PathInPackage": "runtimes/win-x64/native/singlefilehost.exe",
                        "Path": str(host / "runtimes/win-x64/native/singlefilehost.exe")}
            if mode == "wrong-runtime" and component == "frontend":
                metadata["RuntimeIdentifier"] = "win-arm64"
            (build / (component + "-host-pack.json")).write_text(json.dumps({"Items": {"ResolvedSingleFileHostPack": [metadata]}}))
        package_bytes = io.BytesIO()
        with zipfile.ZipFile(package_bytes, "w") as archive:
            archive.writestr("Microsoft.NETCore.App.Host.win-x64.nuspec",
                             '<package xmlns="http://schemas.microsoft.com/packaging/2011/08/nuspec.xsd"><metadata>'
                             '<id>Microsoft.NETCore.App.Host.win-x64</id><version>'
                             + ("10.0.11" if mode == "wrong-version" else VERSION) + '</version></metadata></package>')
            for name, data in BINARIES.items():
                archive.writestr("runtimes/win-x64/native/" + name, data)
            if mode != "missing-license":
                archive.writestr("LICENSE.TXT", "Fixture host license\n")
            archive.writestr("THIRD-PARTY-NOTICES.TXT", "Fixture host notices\n")
        download = root / "host.nupkg"
        download.write_bytes(package_bytes.getvalue())
        if mode in ("apphost-mismatch", "singlefilehost-mismatch"):
            name = "apphost.exe" if mode == "apphost-mismatch" else "singlefilehost.exe"
            (host / "runtimes/win-x64/native" / name).write_bytes(b"different SDK binary")
        # Only the network boundary is stubbed: execute the real packaging code.
        stub = ("import io, pathlib, urllib.request\n"
                "def fixture_download(url, timeout):\n"
                f"    assert url == 'https://api.nuget.org/v3-flatcontainer/{HOST}/{VERSION}/{HOST}.{VERSION}.nupkg'\n"
                f"    return io.BytesIO(pathlib.Path({str(download)!r}).read_bytes())\n"
                "urllib.request.urlopen = fixture_download\n")
        result = subprocess.run([sys.executable, "-c", stub + LICENSE_STEP, str(ROOT), str(release), str(build)],
                                capture_output=True, text=True)
        if expected_error:
            assert result.returncode != 0 and expected_error in result.stderr, (mode, result.stdout, result.stderr)
        else:
            assert result.returncode == 0, (mode, result.stdout, result.stderr)
            notices = release / "licenses" / HOST
            assert (notices / "LICENSE.TXT").read_text() == "Fixture host license\n"
            provenance = json.loads((notices / "PROVENANCE.json").read_text())
            assert provenance["version"] == VERSION and len(provenance["verifiedNativeHostSHA256"]) == 2
            assert HOST + " " + VERSION in (release / "licenses/RESOLVED-PACKAGES.txt").read_text()
            if mode != "nuget":
                assert (notices / "THIRD-PARTY-NOTICES.TXT").is_file()
        print("PASS", mode)


check("nuget")
check("sdk-only")
check("apphost-mismatch", "differs from its matching NuGet package: apphost.exe")
check("singlefilehost-mismatch", "differs from its matching NuGet package: singlefilehost.exe")
check("missing-license", "No license text found for shipped package")
check("wrong-version", "Downloaded host package identity does not match MSBuild")
check("wrong-runtime", "Expected exactly one resolved Windows single-file host")
