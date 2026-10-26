# Sofatap App Store metadata

This is the canonical `asc metadata` directory for iPhone/iPad version **1.0**, staged for the existing TestFlight build **23** on October 26, 2026. English is the primary locale. The public name is Sofatap in every language. Local staging does not establish a completed App Store resubmission; read the live version and review-submission state separately.

| App/site language | App Store locale |
| --- | --- |
| English | en-US |
| Simplified Chinese | zh-Hans |
| Japanese | ja |
| Spanish | es-ES |
| French | fr-FR |
| German | de-DE |
| Brazilian Portuguese | pt-BR |
| Korean | ko |
| Arabic | ar-SA |
| Hindi | hi |
| Russian | ru |
| Indonesian | id |

The 24 JSON files contain app name, subtitle, privacy URL, description, keywords, promotional text, support URL and marketing URL. They omit `whatsNew` for the initial release and contain no review contact, pricing, territory, release-mode or legal-agreement changes. Translation lengths and field formats have been checked; independent native-language editorial review remains pending.

The draft describes manual desktop controls and explains conditional live editing, on-device dictation, computer requirements and experimental TV adapters. Build 23 adds hold-to-drag tolerance to build 22 and includes customizable gesture presets; it does not include the unreleased desktop volume or pointer-speed changes on main. Descriptions now mention iPhone/iPad support, remove the obsolete build-15 double-tap mapping and link desktop receiver 0.8.1 beta.1. They do not advertise autonomous AI operation, universal TV mouse support or lock-screen unlocking. [Build-23 review notes](../app-store-1.0-23-review-notes.txt) give reviewers the matching pairing and gesture path. The [build-15 notes](../app-store-1.0-15-review-notes.txt) remain as historical evidence.

Screenshots and previews are managed separately. Apple can inherit primary-language images when a localization is added; inherited English images are not localized images. Earlier media used actual build-15 device captures. Inspect retained media against build 23, including the old guide's embedded gesture labels, and provide the required iPad screenshot coverage before submitting the universal build. Do not represent a retained build-15 capture as a new build-23 capture. [Apple localization guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information).

## Validate and inspect a draft update

Run from the repository root:

```sh
asc metadata validate --dir docs/app-store/metadata --output json
asc metadata push --app 6822188472 \
  --app-info fedc6f5f-1afd-4162-8160-c0100ba98632 \
  --version 1.0 --platform IOS \
  --dir docs/app-store/metadata --dry-run --output json
```

Review the differences, then omit `--dry-run` to save the draft. Do not add `--allow-deletes`. These files do not change screenshots, privacy questionnaire publication, price, availability or release type. Read back the saved metadata and run `asc validate` afterward.

During the October 14 staging run, this CLI's metadata lookup omitted version locales that a paginated localization list returned. If a plan proposes creating an existing locale, use `asc localizations list --version VERSION_ID --paginate` and update the existing locale with `asc localizations update --version VERSION_ID --locale LOCALE` and the intended fields. Verify all 12 locales through the paginated API result; do not delete or recreate them to make a plan pass.

## Build and review details

Build 23 is `90004eb6-6cdd-42e4-9475-9eecd34d02a6`, from exact release source `c7ad3ab2cb5f86c55839ff349c9026561ec8b68d`. Main also carries build number 23 but contains additional unreleased changes; use the already uploaded build instead of treating a fresh main build as the same package. The existing version is `91096e3e-ef6c-4da6-8e3d-64e22c760a25`. Read its current review state before changing its build; an active review must be withdrawn through the authorized release workflow first.

```sh
asc versions attach-build \
  --version-id 91096e3e-ef6c-4da6-8e3d-64e22c760a25 \
  --build 90004eb6-6cdd-42e4-9475-9eecd34d02a6 --output json
```

The approved review contact is maintained privately, outside the repository. Copy the existing approved Sofatap TestFlight contact into the formal App Store review detail; do not invent or publish contact values. `asc review details-update` accepts `--contact-first-name`, `--contact-last-name`, `--contact-email`, `--contact-phone`, `--demo-account-required=false` and `--notes`. It does not offer a notes-file option. Use a subprocess argument list to read the notes file and private contact JSON without shell interpolation or logging those values.

Saving these drafts and attaching a build do not submit the app for review. Do not run a submit command as part of metadata preparation. The [build-15 readiness audit](../readiness-1.0-15.md) is historical; rerun validation and verify current media, privacy and reviewer access for build 23 before the separately authorized submission.
