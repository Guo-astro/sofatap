# Real Windows updater lifecycle fixture

Run `./desktop/windows/tests/test-update-lifecycle.ps1` only in an ephemeral GitHub-hosted Windows job after the ordinary unit/preview checks. The entry script and harness both require `GITHUB_ACTIONS=true`, `RUNNER_ENVIRONMENT=github-hosted`, Windows, and no existing Sofatap profile, startup shortcut, or process. The harness owns a fresh `%LOCALAPPDATA%/SofaTap` fixture directory and a uniquely named child of `RUNNER_TEMP`; it never runs on the household Gaming PC.

The script publishes the real unmodified WinForms frontend twice (`0.8.0-beta.1` and `0.8.1-beta.1`) as self-contained executables. Both use a dedicated inert host fixture: it only writes a valid native state line and reads the owner's Quit command. It has no networking, desktop input, pairing, audio or production host reference. A failure marker makes the second host emit invalid state and exit.

The driver stages a local ZIP with the real package manifest/digest and starts the old receiver with `--startup`. Production Program discovers the prepared update, copies its own executable, exits, and the real update helper replaces the installation and launches the new receiver. The assertions check:

- successful replacement, the real first-backend-state health acknowledgement and retained old backup;
- failure to start the new host, the real 45-second deadline, rollback and original-host restart;
- exact executable/version identity, custom install files, pairing/TLS preference sentinels, automatic-update preference, and disabled login startup all survive;
- the previous frontend exits and only the expected installed fixture host runs.

A fresh LastAttempt suppresses production HTTP checks, and inherited HTTP/HTTPS proxies point to an unused loopback port as a second guard. Fixture processes have bounded lifetimes. Cleanup validates an ownership marker, enumerates only process executables under the test installation/update cache, kills only those owned trees, and removes only its fresh Sofatap profile. Work folders and backup/results remain available for CI inspection.

The result path is printed as `RUNNER_TEMP/sofatap-update-lifecycle-*/evidence/lifecycle-results.json`. Upload this JSON if desired, rather than the large fixture binaries/ZIPs. The driver and fake host cross-compile on macOS for compile checks, but the lifecycle test itself requires the Windows runner and is not evidence of real phone input acceptance.
