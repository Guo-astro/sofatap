# Android TV receiver updates — October 17, 2026

Candidate: Android receiver **0.2.0-beta.1**, version code **6**. These results verify software behavior; they do not qualify a physical TV or prove an end-user installation.

## Delivered behavior

- Native Check for updates, Install update, Continue installation, Cancel and default-on automatic-download switch, in English, Simplified Chinese and Japanese.
- Daily automatic check/download only while the existing foreground receiver runs. Stop cancels the automatic schedule and in-flight automatic transfer. Opt-out persists. Repeated manual checks are throttled to one minute; server rate limits are honored. No background installer/activity launch.
- Fixed public `chekusu/sofatap` GitHub releases endpoint, ETag caching, at most five 100-release pages, 4 MiB per response, 10-minute operation budget, connect/read timeouts, one ready APK and one temporary transfer, 100 MiB maximum APK. Beta receivers include prereleases; stable receivers only follow stable releases. Android tags are separate from desktop tags, selected by semantic version precedence.
- Exact uploaded asset name and official HTTPS path, mandatory GitHub SHA-256 digest and size, bounded download, restricted GitHub release-asset redirect, package, version name, strictly higher version code and exact current signer-set verification. The same checks run before installation. No uninstall, app-data deletion or permission bypass.
- Android PackageInstaller always requires user confirmation. The explicit TV install button opens unknown-source settings when needed; returning does not install. A further Continue installation action opens Android's confirmation. The result receiver only records state and never opens another app over current TV use. Pending session IDs survive process death, block duplicates, and can be cancelled before retry if the transient confirmation intent was lost.
- `-PsofatapDistribution=play` builds remove `REQUEST_INSTALL_PACKAGES` and set the self-updater gate false. A runtime Play install source also disables self-update. Check for updates opens native Play instead. This is not a submitted or approved Play release.

## Verification

From `android`, with JDK 17 and SDK 36:

```sh
./gradlew :receiver:testDebugUnitTest :receiver:lintDebug :receiver:assembleDebug :receiver:assembleRelease :receiver:assembleDebugAndroidTest
./gradlew -PsofatapDistribution=play :receiver:assembleDebug :receiver:lintDebug
```

- **132 JVM tests passed, 0 failures**. Seventeen new updater tests cover semantic/beta ordering, product filtering and paging, draft/unpublished/missing assets, exact HTTPS paths, mandatory digest/size, same signer/package/version rules, corrupt/truncated/oversize streams, cancellation, ETag/304 cache reuse, rate limits, response redirects and restricted CDN downloads. All network content is an offline fixture; no live APK download.
- Android lint passes; existing warnings remain visible. API-26 compatibility is retained; newer package metadata and installer APIs are SDK-gated.
- The Play-gated APK was built and inspected: self-update flag false and no installation permission in the packaged manifest. The direct build was restored after this check.
- **27 Android instrumentation tests passed** on an owned Android TV API-31 ARM64 emulator launched with `-no-window -no-audio -read-only -no-snapshot`. Seven new tests cover persistent opt-out and Stop, native controls and Activity recreation, Android archive-parser rejection, persistent installer sessions without duplicate creation, session/nonce callback checks, pending-confirmation recovery and cancellation. Existing receiver/input/TLS/IME tests remain enabled. Input-fixture tests disable automatic update requests and restore the preference.
- The emulator runner requires an explicit `emulator-*` serial and verifies `ro.kernel.qemu=1`; it refuses physical targets. The new updater tests do not grant unknown-source permission, start an installer, download a real release or replace the installed APK.

## Not yet verified

- Real PackageInstaller upgrade completion/user confirmation on Sony XRJ-85X95L or Xiaomi MiTV-MOEU0, preservation across that actual upgrade, and OEM background/unknown-source restrictions.
- An actual published next-version asset downloaded from GitHub and installed through the user-facing update flow. The first update-capable package must still be installed by the existing authorized installation route.
- Google Play publication or review.

The API-31 emulator's PackageManager and PackageInstaller state checks are not physical-TV acceptance. All household TVs, iPhones/iPads, and shared-Mac input/display arrangements were untouched by this validation.

## Reference API contracts

- [Android PackageInstaller](https://developer.android.com/reference/android/content/pm/PackageInstaller)
- [Explicit user-action requirement](https://developer.android.com/reference/android/content/pm/PackageInstaller.SessionParams#setRequireUserAction(int))
- [GitHub release metadata](https://docs.github.com/en/rest/releases/releases#list-releases)
