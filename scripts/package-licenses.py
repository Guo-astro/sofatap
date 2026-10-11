#!/usr/bin/env python3
"""Copy the license documents of the packages in a self-contained publish."""

import argparse
import json
from pathlib import Path
import re
import shutil


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--runtime", required=True, choices=["osx-arm64", "osx-x64", "win-x64", "linux-x64", "linux-arm64"])
    parser.add_argument("--host-pack", type=Path, help="MSBuild ResolvedSingleFileHostPack JSON (SDK-installed host packs)")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    assets = json.loads(args.assets.read_text(encoding="utf-8"))
    package_folders = [Path(folder) for folder in assets["packageFolders"]]
    packages = {}
    package_overrides = {}
    for identity, metadata in assets["libraries"].items():
        if metadata.get("type") != "package":
            continue
        name, version = identity.rsplit("/", 1)
        if name.lower() == "microsoft.net.illink.tasks":
            continue  # Build-time tool, not distributed receiver code.
        packages[name.lower()] = version
    for framework in assets["project"]["frameworks"].values():
        for dependency in framework.get("downloadDependencies", []):
            name = dependency["name"].lower()
            if not name.endswith("." + args.runtime):
                continue
            match = re.fullmatch(r"\[([^,\]]+),\s*([^\]]+)\]", dependency["version"])
            if not match or match[1] != match[2]:
                raise SystemExit("Expected an exact runtime version for " + name)
            packages[name] = match[1]
    host_name = "microsoft.netcore.app.host." + args.runtime
    if args.host_pack:
        hosts = json.loads(args.host_pack.read_text(encoding="utf-8"))["Items"]["ResolvedSingleFileHostPack"]
        if len(hosts) != 1 or hosts[0].get("RuntimeIdentifier") != args.runtime:
            raise SystemExit("Expected exactly one resolved single-file host for " + args.runtime)
        package = Path(hosts[0]["PackageDirectory"])
        if package.parent.name.lower() != host_name or not re.fullmatch(r"\d+\.\d+\.\d+(?:[-+].+)?", package.name):
            raise SystemExit("Resolved host package directory has an unexpected identity")
        packages[host_name] = package.name
        package_overrides[host_name] = package
    required = {
        "microsoft.netcore.app.runtime." + args.runtime,
        "microsoft.aspnetcore.app.runtime." + args.runtime,
        host_name,
    }
    if not required.issubset(packages):
        raise SystemExit("Resolved runtime packages are missing from the restore manifest")
    args.destination.mkdir(parents=True, exist_ok=True)
    resolved = []
    document_names = {"license", "license.txt", "license.md", "third-party-notices.txt", "thirdpartynotices.txt", "notice", "notice.txt"}
    for name, version in sorted(packages.items()):
        package = package_overrides.get(name) or next((folder / name / version for folder in package_folders if (folder / name / version).is_dir()), None)
        if package is None:
            raise SystemExit("Resolved package is missing from the cache: " + name)
        destination = args.destination / name
        destination.mkdir(exist_ok=True)
        documents = [file for file in package.iterdir() if file.is_file() and file.name.lower() in document_names]
        if name == host_name and package.parent.parent.name == "packs":
            # SDK-installed host packs omit package-level notices; the matching
            # SDK distribution carries their MIT license and third-party notices.
            sdk_root = package.parent.parent.parent
            documents.extend(file for file in sdk_root.iterdir() if file.is_file() and file.name.lower() in document_names)
        if name == "qrcoder" and version == "1.7.0":
            # The package omits the MIT text; this copy is pinned to its upstream source.
            documents.append(root / "licenses/qrcoder/LICENSE.txt")
        if not any(file.name.lower().startswith("license") for file in documents):
            raise SystemExit("No license text found for shipped package: " + name + " " + version)
        for document in documents:
            shutil.copyfile(document, destination / document.name)
        resolved.append(name + " " + version)
    (args.destination / "RESOLVED-PACKAGES.txt").write_text(
        "Resolved package licenses included in this release:\n" + "\n".join(resolved) + "\n", encoding="utf-8"
    )
    print("Included license documents for " + str(len(resolved)) + " resolved packages")


if __name__ == "__main__":
    main()
