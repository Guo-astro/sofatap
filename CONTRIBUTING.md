# Contributing to Sofatap

Thanks for helping improve [Sofatap](https://github.com/chekusu/sofatap).

- Open an issue describing the device, OS versions, expected behavior and a reproducible example. Never include pairing QR codes, tokens, private keys or personal draft text.
- Keep changes focused. Update `PROTOCOL.md` when changing the wire format and include both client and receiver implications.
- Run the checks listed in `README.md`. State which checks ran and distinguish dry-run or simulator evidence from physical-device verification.
- Preserve explicit text sending, certificate pinning, authentication, input release on disconnect and the rule against automatic replay.
- Do not add arbitrary command execution or weaken TLS validation to make tests pass.

Use **Sofatap** as one word in every public surface, including UI, images and video copy. Keep the English, Chinese and Japanese READMEs aligned; see [brand guidance](docs/BRAND.md).

Pull requests are welcome. Contributions are licensed under the repository's [MIT license](LICENSE).

## Maintainer synchronization

After checks pass and changes are committed, maintainers can run `python3 scripts/notify-sandbank.py --push` to push the current clean branch to `chekusu/sofatap` and notify Sandbank Dev through Yobiru. Without `--push`, the script only sends if the exact commit is already the tip of that branch on origin. `--branch main` can assert the expected current branch. This internal workflow is not required for external contributions.

The script discovers the installed Yobiru CLI, or accepts its file path in `YOBIRU_CLI`; `YOBIRU_HOME` selects an existing configured data home. `SOFATAP_SYNC_TARGET` or `--target` selects the known Sandbank Dev `host/agent`. No receiver, permissions or background service is configured by this script.

Failed sends return a nonzero exit status and retain a pending receipt inside `.git/sofatap-sync/` (the worktree's Git directory when applicable). Run `python3 scripts/notify-sandbank.py --retry` to retry; this does not publish local changes and is safe while the working tree has other edits. Every retry rechecks origin. If the branch has advanced, publish/notify its new head instead and review the older pending receipt. A timeout may have delivered the original request, so retries include the same request key for recipient deduplication. HTTP 200/202 means delivery; only a matching authenticated reply confirms the server's fast-forward synchronization.
