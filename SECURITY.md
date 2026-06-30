# Security

Remove Background processes images **entirely on-device**. Its only network use is one-time
model downloads and Sparkle update checks (which send just the app version, macOS version,
and CPU architecture). This document records the project's security posture and the
decisions behind a pre-1.0 audit.

## Posture

- **Transport** — every model download and the update appcast use HTTPS with default
  certificate validation; there are no insecure-load (ATS) exceptions.
- **Model integrity** — each model is pinned to an immutable HuggingFace **commit SHA** and
  verified against a hard-coded **SHA-256** after download; a mismatch is discarded.
- **Untrusted model output** is bounds-checked before use, so a model that lies about its
  output shape can't drive an out-of-bounds read or a huge allocation.
- **Updates** — Sparkle updates are **EdDSA-signed** (verified against the embedded public
  key) and the app itself is **Developer ID-signed + notarized**.
- **Signing** — hardened runtime, signed with **no** weakening entitlements (no
  `disable-library-validation`, no JIT). The app contains no `dlopen`/`exec`/dynamic code.
- **CI/CD** — release secrets run only on owner-pushed tags; all GitHub Actions are pinned
  to commit SHAs; the `pull_request_target` governance job runs no pull-request code.

## Documented decisions (low-severity audit items)

- **App Sandbox — not enabled (deferred).** The app ships with Developer ID (not the Mac App
  Store), where sandboxing isn't required. It would help contain a model-parser exploit, but
  complicates user-file access, the model cache, and Sparkle; it's a candidate for a future
  release rather than a 1.0 blocker.
- **Notarization credentials.** CI uses an Apple ID + app-specific password via `notarytool`;
  the password is passed once on an ephemeral runner and masked in logs. Moving to an App
  Store Connect **API key** would remove the password entirely — a planned future improvement.
- **Certificate pinning — declined.** System CA trust, combined with the pinned model commit
  SHAs and EdDSA-signed updates, already covers the realistic threats. Pinning would add
  maintenance and break whenever an upstream certificate rotates.

## Reporting

This is a non-commercial, **as-is** project with no support. Security issues can be reported
through GitHub's **private vulnerability reporting** on this repository. There is no
guaranteed response time.
