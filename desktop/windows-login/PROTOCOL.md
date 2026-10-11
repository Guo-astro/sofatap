# Optional Windows password sign-in protocol v1

This is an opt-in development component, separate from normal Sofatap input. It does not use `SendInput`, remote clipboard, stored PC-side passwords, or Codex. Installing it adds a Credential Provider and a LocalSystem service. It never replaces, filters, or disables Windows providers.

## Enrollment

The initial pilot requires an already signed-in **local or personal Microsoft Windows profile that can approve administrator elevation as the same account**. `NetUserGetInfo` level 24 distinguishes local and personal Microsoft identities and binds the exact local SID. Domain, Entra, Windows Hello PIN, passwordless accounts and biometric credential handling are unsupported. A personal Microsoft account must have an actual password; no account setting is changed. The installer refuses alternate-account elevation. No password is required to install.

The service owns a distinct TLS certificate and a random 32-byte bearer credential for one enrollment. Its private configuration is machine-DPAPI encrypted in `%ProgramData%/Sofatap/Login/service.dat`, with SYSTEM/Administrators-only ACLs. The receiver capability is separately CurrentUser-DPAPI protected at `%LOCALAPPDATA%/SofaTap/unlock-capability.dat` and bound to the ordinary receiver certificate fingerprint. This is not the existing pairing bearer. Re-enrollment is explicit, not automatic certificate/token replacement.

The existing authenticated, certificate-pinned receiver's `hello.unlock` contains exactly (provider is `windows-local-password` or `windows-microsoft-password`; accountName remains the local profile alias):

```json
{"version":1,"port":53320,"fingerprint":"64 lowercase hexadecimal characters","token":"43 base64url characters","deviceId":"UUID","accountName":"fixed local account","accountSid":"S-1-5-21-...","provider":"windows-local-password"}
```

The on-disk object additionally contains `receiverFingerprint`; it must never be used to redirect the phone to a new host. The phone uses the already paired host and exact service port 53320, pins the service certificate, and caches capability only after explicit user enrollment. The phone password is kept under Face ID protected device-only Keychain access by the iOS implementation. Phone biometrics authorize releasing the password; Windows still verifies the account password.

## HTTPS

Every call requires `Authorization: Bearer <unlock token>`, the pinned TLS connection and no browser `Origin`. The listener only accepts loopback/private LAN source addresses; installer firewall allowance is Private / TCP 53320 / LocalSubnet. No public/internet relay is enabled. JSON is camelCase; timestamps are ISO 8601. Passwords are never ordinary `/control` messages.

- `GET /v1/status` → `{version:1, accountSid, deviceId, accountName, machineName, state}`. State is `ready` for an already unlocked console, `locked` when its provider is live and eligible, or `unavailable`. `ready` is not an authentication receipt.
- `POST /v1/challenge` with `{}` → `{attemptId, nonce, expiresAt, accountSid, deviceId, sessionId}`. Attempt ID is UUID, nonce is 43 base64url characters, TTL is 30 seconds measured monotonically in the service. It binds the configured account/device, service instance, physical console session and provider generation. No client-controlled account/session is accepted.
- `POST /v1/unlock`, `Content-Type: application/json`, with `{attemptId,nonce,password}` → HTTP 202 and `{attemptId,status:"waiting_for_windows",accountSid,deviceId}`. Limits: 16 KiB body; 1–1024 UTF-16 password units; no NUL; duplicate/unknown fields rejected. Nonce consumption is atomic. A transport response does not mean Windows accepted the password. Never automatically resend a password after timeout.
- `GET /v1/attempt/<UUID>` → `{attemptId,status,accountSid,deviceId}`. Status: `waiting_for_windows`, `unlocked`, `rejected`, `expired`, `unavailable`, `cancelled`, or `unknown`. Only matching Credential Provider `ReportResult(STATUS_SUCCESS)` plus an unlocked physical console belonging to the configured SID can produce `unlocked`.
- `DELETE /v1/attempt/<UUID>` → same status shape. Before handoff it cancels and erases the secret. After handoff status is `unknown`: cancellation cannot promise to retract a credential already submitted to Windows.

One outstanding attempt; at most six challenges per minute and three credential submissions per five minutes for this enrollment, independent of HTTP connection. In-memory attempts and limits reset only when the administrator-controlled service restarts. Old challenges cannot survive that restart. Retain at most 64 terminal status entries. No polling response contains passwords, tokens or Windows error text. Generic errors use `{error:"stable_code"}` with HTTP 409 or 429.

## Local provider bridge

The non-public pipe `\\.\pipe\Sofatap.Login.v1` uses SYSTEM-only DACL, first-instance creation and remote-client rejection. The service checks the impersonated client's SYSTEM identity, authenticated client PID image `System32\LogonUI.exe`, and active console session. The provider checks the pipe server PID against the real `SofatapLogin` SCM service and opens with identification-only SQOS, preventing a pipe impostor from obtaining an impersonation token.

All integers are little endian. GUIDs use Windows in-memory / .NET `Guid.ToByteArray` ordering. Client request is exactly 48 bytes: magic uint32 `0x5346544C`, operation uint32 (1 poll / 2 ReportResult), session uint32, provider generation GUID16, attempt GUID16, signed Windows NTSTATUS int32. Provider generation changes on usage/advice context changes.

Poll response uint32 0 means no credential. Response 1 is followed by attempt GUID16, account UTF-16 unit count uint16, password unit count uint16, remaining TTL milliseconds uint32, account UTF-16LE bytes then password UTF-16LE bytes. These are the configured account and one-shot secret only. The provider keeps a received password for **at most five seconds and no longer than remaining service TTL**, wipes after serialization/deselection/context change, and does not retry it. ReportResult response is a zero uint32 acknowledgement. Pipe I/O is bounded.

The V2 provider matches its enrolled SID against the user array supplied by LogonUI. Local accounts use protected-password `KERB_INTERACTIVE_UNLOCK_LOGON` for Negotiate. Personal Microsoft accounts use the OS-qualified `MicrosoftAccount\principal` with `CredPackAuthenticationBuffer` and `CRED_PACK_PROTECTED_CREDENTIALS | CRED_PACK_ID_PROVIDER_CREDENTIALS`; they never fall back to a local SAM password. Provisioning freezes the private Microsoft principal; relinking an account invalidates the enrollment even if the local SID is unchanged. LSA remains the authentication authority. Existing Windows sign-in paths remain available.

## Acceptance still required

Build/state tests are not evidence of a real login. Use an explicitly approved disposable Windows account/VM first: correct/wrong/changed password; lock/unlock; restart before first login; multiple users; no provider; service failure; session handoff; cancel/expiry/replay; certificate mismatch; account relinked to a different Microsoft identity; password-free logs; uninstall/recovery. A connected phone must not show success merely because a POST or pipe write succeeded. Windows may require choosing its Sofatap sign-in option; automatic tile activation needs real-version verification. Secure Attention Sequence policies, BitLocker/preboot, sleeping hardware and nonlocal credential types are out of scope.
