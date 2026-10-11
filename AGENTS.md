# Sofa Tap development

Sofa Tap is maintained in the public `chekusu/sofatap` GitHub repository. Keep product development here and coordinate the Sandbank Dev copy through Yobiru. GitHub is the sole source distribution channel: send repository/branch/commit references, not source archives or source-file attachments, through Yobiru.

## Standing synchronization instruction

The user has authorized notifying Sandbank Dev after each logical change is validated, committed and successfully pushed to GitHub. Use `python3 scripts/notify-sandbank.py --push` to publish the current clean branch and send that notification, or omit `--push` after an independently completed push. The script verifies the exact remote branch and full commit SHA before sending. Set `SOFATAP_SYNC_TARGET=sandbank-dev/AGENT` only when the intended agent is known; otherwise the default is `sandbank-dev`.

If delivery fails, report the blocker and retry with `python3 scripts/notify-sandbank.py --retry`. Pending receipts stay in the Git directory and must not be committed or published. HTTP 200/202 confirms delivery only; require an authenticated Yobiru reply matching the sent message ID before saying the server synchronized. A 403 is a policy block: report it and do not change an allowlist without explicit user authorization.

Ask the receiving agent to fetch and synchronize using fast-forward-only Git operations. Never instruct it to discard, reset, stash or overwrite its local work. Keep pairing tokens, QR codes, signing assets, credentials and private user data out of commits and messages.

## Receiver tests on the shared Mac

Use Yomado to place receiver acceptance-test windows on a virtual display before the next desktop test. Keep the user's normal displays and active work undisturbed. Do not make the virtual display primary or change the physical display arrangement. Verify the test windows and input target are isolated before sending real mouse or keyboard events; moving a window alone does not prove input isolation. If isolation cannot be verified, defer live input tests. Restore any test-window placement after testing.
