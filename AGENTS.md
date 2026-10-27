# Sofatap development

Sofatap is maintained in the public `chekusu/sofatap` GitHub repository. Keep product development here and coordinate the Sandbank Dev copy through Yobiru. GitHub is the sole source distribution channel: send repository/branch/commit references, not source archives or source-file attachments, through Yobiru.

The project-root `.sandbank/` directory, including `.sandbank/handoff/`, contains the user's local development material and must not be committed. Keep `/.sandbank/` in the root `.gitignore`. If files there are already tracked, preserve them on disk and remove only their Git index entries with `git rm -r --cached -- .sandbank`; verify that both existing files and future generated files are ignored before committing or integrating changes.

## Product scope and development order

Keep the two core functions separate:

- **Free manual remote:** the user directly controls a computer or TV with the phone touch surface, mouse gestures and text input. Existing keyboard and speech-to-text dictation are basic input, not paid autonomous operation.
- **Paid voice automation:** the user states a goal and Sofatap plans, executes and verifies a sequence of actions. Build this for Windows, macOS and Linux first, then extend it to televisions.

The next feature priority is **free manual TV control**, ahead of integrating the paid agent runtime. After that, implement paid desktop automation, followed by paid TV automation. See `docs/ROADMAP.md`. Keep first-release maintenance and acceptance work distinct from this feature sequence.

Within free TV control, prioritize the **Android/Google TV receiver feasibility milestone**. Keep the existing LG webOS preview as a separate adapter; LG hardware qualification is not a prerequisite for Android work. A common Android receiver package does not prove global mouse injection or compatibility with every TV app.

Treat TV mouse/pointer control as a real capability to verify. Directional focus navigation is a separate capability and must not be described as equivalent mouse support. Do not claim every TV model or application is supported before device-level acceptance. Manual control must not silently start an AI task, require a model account or depend on paid inference.

## Standing synchronization instruction

The user has authorized notifying Sandbank Dev after each logical change is validated, committed and successfully pushed to GitHub. Use `python3 scripts/notify-sandbank.py --push` to publish the current clean branch and send that notification, or omit `--push` after an independently completed push. The script verifies the exact remote branch and full commit SHA before sending. Set `SOFATAP_SYNC_TARGET=sandbank-dev/AGENT` only when the intended agent is known; otherwise the default is `sandbank-dev`.

If delivery fails, report the blocker and retry with `python3 scripts/notify-sandbank.py --retry`. Pending receipts stay in the Git directory and must not be committed or published. HTTP 200/202 confirms delivery only; require an authenticated Yobiru reply matching the sent message ID before saying the server synchronized. A 403 is a policy block: report it and do not change an allowlist without explicit user authorization.

Ask the receiving agent to fetch and synchronize using fast-forward-only Git operations. Never instruct it to discard, reset, stash or overwrite its local work. Keep pairing tokens, QR codes, signing assets, credentials and private user data out of commits and messages.

## Receiver tests on the shared Mac

Use Yomado to place receiver acceptance-test windows on a virtual display before the next desktop test. Keep the user's normal displays and active work undisturbed. Do not make the virtual display primary or change the physical display arrangement. Verify the test windows and input target are isolated before sending real mouse or keyboard events; moving a window alone does not prove input isolation. If isolation cannot be verified, defer live input tests. Restore any test-window placement after testing.

## Brand and language

The public brand is **Sofatap**, one word with only the initial S capitalized. Use this spelling in UI, store metadata, README text, web copy, promotional images, video titles, subtitles and narration scripts. Never separate sofa and tap. English is the default `README.md`; keep `README.zh-CN.md` and `README.ja.md` aligned and linked. The proposed Chinese-market name is **沙发瘫**, using 瘫 as in 瘫倒; do not silently change installed app names to the Chinese proposal.

Keep compatibility identifiers (such as existing `SofaTap` executable/project names, bundle IDs and credential paths) stable. Preserve literal historical artifact paths and verbatim generation provenance, clearly labeled as historical. New marketing assets must use the current spelling. See `docs/BRAND.md`.
