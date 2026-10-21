# Security reports

Audifern is an early project. Compatibility and security testing are limited to
the devices and paths documented in [hardware verification](docs/hardware-verification.md).
There is no separate maintained release branch yet; fixes target the current
development version.

## Report privately

Use the repository host's **Security → Report a vulnerability** option when it
is available. If a private reporting channel has not been enabled, open an
issue titled **Private security report requested**, with no exploit, device or
credential details, so a maintainer can arrange a private channel.

Include a concise description, affected version/commit, relevant device model
and reproducible steps using synthetic data where possible. Distinguish an
observed result from a suspected issue. Do not include authentication keys,
serials, device addresses, raw hearing-aid captures or medical records in a
public issue. Do not perform a hearing-changing operation merely to prove a
report.

## Areas that need particular care

- Bluetooth parsers must reject malformed, oversized or unsupported data.
- A control must use fresh capabilities and ranges, preserve unrelated fields,
  and confirm the change by readback.
- Session recovery must close only the application's own channel and leave
  another client's connection alone.
- Credentials, medical records and identifiers must stay out of logs, bundles,
  fixtures, screenshots and source history.
- Imported/exported files and local storage must preserve existing user data
  on errors and avoid following unexpected symbolic links.

Clinical fitting, firmware updates, arbitrary memory access and guessed device
writes are outside the implemented companion scope. A contract found in static
research does not by itself establish a safe or supported runtime operation.

Use [GitHub private vulnerability reporting](https://github.com/sabino/audifern/security/advisories/new) for a private report.

## Public release automation

The source and build logs are public; Apple private keys are not. Apple signing
credentials belong only in the main-only `apple-notarization` GitHub environment.
Forks and pull-request CI builds must never receive them. Do not introduce
privileged `pull_request_target` or `workflow_run` jobs that execute PR code.

Only the maintainer may update main or create version tags. Main requires signed
commits and all four GitHub Actions checks; published version tags cannot be
moved or deleted. Actions are SHA-pinned and allowlisted. The credential setup
tool checks these server-side policies before exporting any signing identity.
See [distribution](docs/distribution.md#ci-and-release-trust) for the release
flow and one-time credential setup.

Trusted main code, the GitHub administrator account and signing runners remain
inside the security boundary. A compromise there can expose or misuse signing
credentials even when secret storage is encrypted. Review code before merging,
keep account authentication secure, use dedicated revocable Apple API keys,
and revoke or rotate affected credentials if a leak is suspected.
