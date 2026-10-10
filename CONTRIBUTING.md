# Contributing to Tiltro

Thanks for helping improve [Tiltro](https://github.com/chekusu/tiltro).

- Open an issue describing the device, OS versions, expected behavior and a reproducible example. Never include pairing QR codes, tokens, private keys or personal draft text.
- Keep changes focused. Update `PROTOCOL.md` when changing the wire format and include both client and receiver implications.
- Run the checks listed in `README.md`. State which checks ran and distinguish dry-run or simulator evidence from physical-device verification.
- Preserve explicit text sending, certificate pinning, authentication, input release on disconnect and the rule against automatic replay.
- Do not add arbitrary command execution or weaken TLS validation to make tests pass.

Pull requests are welcome. Contributions are licensed under the repository's [MIT license](LICENSE).
