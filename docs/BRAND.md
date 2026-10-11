# Sofatap brand guidance

The global product name is **Sofatap**: one word, with only the initial **S** capitalized. Lowercase `sofatap` is appropriate for URLs and technical identifiers. Keep the same spelling in English, Chinese and Japanese copy.

Apply this name consistently to app titles, permission descriptions, notifications, store listings, documentation, websites, illustrations, screenshots, promotional video titles, subtitles, end cards and narration scripts. Do not insert a space between sofa and tap or capitalize the internal t in public copy.

## Chinese-market name proposal

**沙发瘫** uses **瘫**, as in 瘫倒. It evokes relaxing on a sofa while controlling a computer with a phone, and its rhythm echoes Sofatap. Suggested presentation:

> 沙发瘫 · Sofatap  
> 躺在沙发，电脑在手。

This is the proposed Chinese name; the current app display name remains **Sofatap**. In Japanese, retain **Sofatap** rather than inventing a separate product name.

## Describe the product accurately

Sofatap turns an iPhone into a single-screen gesture mouse and voice/text input surface for a living-room computer. The TV displays the computer; the phone controls it. Windows, macOS and supported Linux desktops use native pairing windows. Connection uses the local network, not Bluetooth. Development version 0.5.0 adds an on-device speech button when supported, with keyboard/Typeless fallback and optional focused-field detection; Sofatap sends reviewed text when the user chooses Send. Earlier downloadable alpha versions retain their previous UI. See [interaction direction](INTERACTION.md).

Keep implementation and verification claims distinct. Concept illustrations are labeled as illustrations. Do not present generated UI as a screenshot, a passed hardware test, or an App Store listing. Carry current platform limits forward from the README and verification records.

## Current assets and languages

- [English README](../README.md) is the default; [简体中文](../README.zh-CN.md) and [日本語](../README.ja.md) provide equivalent versions.
- [Living-room hero](images/sofatap-living-room.png): generated with the built-in imagegen tool, visually reviewed, and shared by all three READMEs. [Exact generation prompt](brand/living-room-image-prompt.txt).
- The app icon and icon concepts contain no text, so this spelling update does not change their artwork.
- No promotional video is currently tracked in this repository. Future video work must follow the spelling above.

Keep stable code and compatibility identifiers such as existing `SofaTap` project/executable names, archive filenames, bundle IDs and credential paths. Literal filenames in immutable published archives and verbatim historical generation prompts retain their original spelling and must be labeled as historical. They are evidence and compatibility references, not reusable marketing copy. Never alter a signed release archive to change branding in place.
