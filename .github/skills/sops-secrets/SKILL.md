---
name: sops-secrets
description: >
    Safely create, review, generate, and validate SOPS-encrypted dotenv secrets.
    Use when adding or editing secret.sops.env files, configuring Age keys through
    1Password, generating one-time random values, or troubleshooting SOPS access.
argument-hint: 'Describe the encrypted secret file and variables to create or review'
---

# Manage SOPS Secrets Safely

## Hard Safety Rules

- Never print an Age private key or decrypted secret value.
- Never print the configured `op://` reference or the value of `SOPS_AGE_KEY_CMD`; use a redacted command in notices.
- Before every operation that may access 1Password, provide the [advance disclosure](#before-every-1password-operation), including indirect access through SOPS or helpers.
- Never redirect decrypted SOPS output to a plaintext file.
- Never commit plaintext `.env`, key, editor backup, or temporary generated files.
- Keep `secret.sops.env` encrypted before and after every operation.
- Use `scripts/generate-sops-secrets.sh` only for generate-once bootstrap. Existing values are preserved; rotation is manual.
- Never run the generator concurrently against the same file.
- Use only `VARIABLE=BYTE_COUNT` arguments for random values. Do not pass user-supplied credentials or shared values.
- Use disposable Age identities in tests. Never use a production key in CI or test fixtures.
- `SOPS_BIN`, when set, is a non-secret executable path or command name — never put a key, passphrase, or other secret value in it.

## Before Every 1Password Operation

Provide a **user-visible preamble followed by the commands** before invoking
anything that may access 1Password. This applies even when already
authenticated: account checks, sign-in, SOPS-triggered key reads, generation,
editing, validation, troubleshooting, and retries all need advance disclosure.
Include:

1. **Exact commands:** Show the command(s) about to run, including helper
   arguments and underlying key-access commands. Resolve non-secret inputs
   such as target paths, variable names, and byte counts. Redact the key
   reference as `op read "<reference withheld>"` or
   `-AgeKeyReference '<reference withheld>'`; never print the configured
   reference to explain it. A redacted command is a preview, not a command
   to paste unchanged. Describe `op read` as SOPS-triggered, not a standalone
   preflight to execute.
2. **Purpose:** Explain what each command or phase will do and why it needs
   1Password, rather than saying only "checking secrets" or "running setup."
3. **Read/write scope:** State that the planned 1Password data access is
   **read-only**; no vault items will be created or changed. Identify
   authentication/session changes separately. Name every local encrypted
   file to be created or changed, or explicitly say none. Include temporary
   ciphertext and conditional replacement or failure cleanup when applicable.
4. **Privacy:** Explain how the Age key reaches SOPS without being printed,
   how decrypted data is discarded or consumed in memory, and how generated
   values travel through stdin without appearing in arguments, history, logs,
   or plaintext files. For `sops edit`, explicitly disclose the SOPS-owned
   temporary plaintext editor file outside the repository; do not claim that
   editing is entirely in-memory.
5. **Authorization scope:** Tell the user that the 1Password prompt grants
   CLI access broadly, even though the planned commands are narrow and
   read-only. The plan is a commitment about intended use, **not** a
   technically enforced least-privilege, per-command grant.

For an automated helper, one upfront notice may cover a batch **only if it
explicitly enumerates every possible key-access operation**, with exact
commands, individual phases, generation count (or conditional maximum),
variable names, byte counts, and branch conditions. Read the helper first;
expand loops and conditional accesses in the plan rather than hiding them
behind a single helper command or vague log message. Identify generated
temporary paths by their naming pattern when their random suffix is not yet
known. If the plan changes, stop and show a new notice before proceeding.

Use this phase checklist to build the numbered command plan; it is not a
substitute for showing the actual commands and inputs:

| Workflow                     | Phases to announce individually before invocation                                                                                                                                                                                                                                                                                                                                                                                                       |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Native PowerShell preflight  | `op signin` to authenticate, then `op whoami` to verify the account; both discard output.                                                                                                                                                                                                                                                                                                                                                               |
| `New-SopsEncryptedEnvFile`   | Perform the native preflight; encrypt the non-secret template; generate the stated number of values with one `sops set --value-stdin` per variable; check encryption metadata; decrypt for final in-memory validation. Each set and validation decrypt can trigger `op read`.                                                                                                                                                                           |
| `Add-SopsGeneratedEnvSecret` | Check metadata; perform the native preflight; decrypt to inspect state in memory; for each requested variable, conditionally add a missing encrypted sentinel and then generate its value through separate `sops set --value-stdin` calls; decrypt the encrypted working copy for final validation before replacement. Enumerate both possible sets per variable and the no-op branch for preserved values. Each decrypt and set can trigger `op read`. |
| `Open-SopsEncryptedFile`     | Check metadata; perform the native preflight; run `sops edit`, which can trigger `op read`, and re-encrypt after the editor closes; check saved encryption metadata.                                                                                                                                                                                                                                                                                    |
| Bash generator and validator | Generator: decrypt once per requested variable, conditionally set each remaining sentinel, then decrypt the encrypted working copy before replacement if changes were made. Validator: structural checks followed by a separate validation decrypt. Each decrypt and set can trigger `op read`.                                                                                                                                                         |

Metadata/structural checks do not need key access. Counts of
potential key-access phases are not promises about the number of prompts.
The native module emits progress logs, but those logs **do not replace the
agent's advance disclosure** before invoking an automated sequence.

After a timeout, denial, or failure, do not retry automatically. Explain the
failure without exposing sensitive output, show the **new exact retry plan**
(including repeated sign-in, account checks, and key reads), ask whether the
user is ready, and wait for their response before retrying. An earlier batch
notice or authorization does not cover a retry.

## Implementation Contract

`scripts/generate-sops-secrets.sh` and `scripts/validate-sops-secrets.sh` share
`scripts/sops-common.sh`, so both invoke SOPS through identical logic instead
of two subtly different copies:

- **Default invocation**: `mise exec -- sops` (requires `mise` on `PATH`).
- **`SOPS_BIN` override**: set `SOPS_BIN` to an explicit executable path or a
  bare command name resolvable on `PATH` to bypass `mise exec` entirely. A
  path-like value (contains `/`) must reference an existing, executable
  regular file; a bare name must resolve via `command -v`. The shared helper
  validates this before use and fails with a clear error otherwise. Once
  resolved, `${SOPS_BIN}` is invoked directly with a safely quoted argv — no
  shell re-interpretation of arguments, so unusual paths (including ones with
  spaces, as on Windows) are handled correctly.
- **`SOPS_AGE_KEY_CMD`** continues to work unchanged with either invocation
  method. When set, the shared helper unsets `SOPS_AGE_KEY` and
  `SOPS_AGE_KEY_FILE` for that invocation only, so the mutually exclusive key
  sources can never leak into each other.

Do not construct a raw `sops` or `mise exec -- sops` call by hand in new
tooling — source `scripts/sops-common.sh` and use its `run_sops` function so
new scripts automatically pick up the same `SOPS_BIN`/`mise` contract.

## Preferred 1Password Setup

Use SOPS-native `SOPS_AGE_KEY_CMD`. The reference below is a placeholder; replace every angle-bracket component:

```sh
export SOPS_AGE_KEY_CMD='op read "op://<vault>/<item>/<field>"'
```

Require the 1Password CLI, an authenticated account, and an unlocked 1Password Desktop session:

```sh
command -v op >/dev/null
op account list >/dev/null
op whoami >/dev/null
```

Do not execute or shell-evaluate `SOPS_AGE_KEY_CMD` yourself. SOPS tokenizes the
value and invokes the executable directly, so a shell-based preflight would have
different semantics and could execute metacharacters that SOPS treats as plain
arguments.

Before editing, prove that SOPS can use the configured identity while discarding decrypted output:

```sh
target='services/<app>/secret.sops.env'
mise exec -- sops decrypt --input-type dotenv --output-type dotenv "${target}" >/dev/null
```

`<app>`, `<vault>`, `<item>`, and `<field>` are placeholders, not literal production references.
Valid 1Password output contains one supported Age identity. A normal multiline
identity file may surround it with comments. A password field flattened into
one comment-prefixed line is invalid because the identity becomes part of the
comment; store only the `AGE-SECRET-KEY-...` line or preserve real newlines in a
Secure Note.

## Generate Random Values Once

Create each random variable with the exact plaintext sentinel `GENERATE`, then encrypt the dotenv file in place. Once the encrypted template exists, run:

```sh
bash scripts/generate-sops-secrets.sh services/<app>/secret.sops.env VARIABLE=BYTE_COUNT [VARIABLE=BYTE_COUNT ...]
```

The helper:

- accepts byte counts from 16 through 1024;
- changes only requested variables whose decrypted value is exactly `GENERATE`;
- preserves existing values, including previously generated values;
- succeeds without rewriting ciphertext when no requested sentinel remains;
- writes through an encrypted temporary file and replaces the target only after SOPS verifies it.

Rotation is deliberately out of scope. Rotate an existing value manually with `sops edit`.

## Validate (Canonical)

`scripts/validate-sops-secrets.sh` is the canonical, reusable validator for a
`secret.sops.env` file. It never writes plaintext to disk and never prints a
decrypted value — only variable names and error text are ever emitted.

```sh
bash scripts/validate-sops-secrets.sh services/<app>/secret.sops.env REQUIRED_VAR [REQUIRED_VAR ...]
```

It:

- structurally verifies the target is a SOPS-encrypted dotenv file (same check `generate-sops-secrets.sh` uses) before attempting decryption;
- streams the decrypted output directly into an `awk` parser via a pipeline — the plaintext is never assigned to a shell variable or written to a file at any point;
- confirms every `REQUIRED_VAR` argument is present in the decrypted output;
- rejects the exact sentinel `GENERATE` or `CHANGE_ME` on **any** variable in the file, not just the required ones — an unresolved sentinel anywhere is a failure;
- exits `0` only when the file decrypts, every required variable is present, and no sentinel remains; exits `1` on a validation failure (see stderr) or `2` on a usage error.

It can also be sourced (`. scripts/validate-sops-secrets.sh`) to call the
`validate_sops_secrets` function directly from another script or test
helper — sourcing only defines the function and loads
`scripts/sops-common.sh`; it does not execute anything.

Use this as the standard post-generation and post-edit check instead of
hand-rolling a decrypt-and-grep pipeline.

## Safely Review and Edit

Use VS Code as the SOPS editor. Disclose that SOPS uses a temporary plaintext
editor file outside the repository; this is not an entirely in-memory operation:

```sh
target='services/<app>/secret.sops.env'
SOPS_EDITOR='code --wait' mise exec -- sops edit "${target}"
```

Replace remaining `GENERATE` sentinels and any required user-supplied or shared values, then save and close the editor so SOPS re-encrypts the file.

For automation, use `sops set --value-stdin` with a correctly JSON-encoded value so the secret does not appear in command arguments or shell history. The generate-once helper uses this pattern. Prefer `sops edit` for human changes rather than constructing a `sops set` command manually.

After editing, prefer the [canonical validator](#validate-canonical) over a
hand-rolled check:

```sh
bash scripts/validate-sops-secrets.sh "${target}" REQUIRED_VAR [REQUIRED_VAR ...]
```

Then run the repo-hygiene checks the validator does not cover — these confirm
the file is still tracked as expected by git, that no secret leaked into the
working tree, and that no temporary generated file was left behind:

```bash
git status --short -- "${target}"
mise exec -- gitleaks dir --redact .
leftover="$(
    find "$(dirname "${target}")" -maxdepth 1 -type f \
        -name "$(basename "${target}").generated.*" -print -quit
)"
test -z "${leftover}" || {
    printf 'ERROR: generated temporary file remains: %s\n' "${leftover}" >&2
    exit 1
}
unset leftover
```

**Manual/troubleshooting equivalent.** Use this only when the required
variable list is not known ahead of time, or to narrow down why the
validator failed — it performs the same structural-then-decrypt checks by
hand. `sops filestatus` reports plaintext files with a successful command
exit, so its JSON result must be inspected explicitly:

```bash
status="$(mise exec -- sops filestatus "${target}")"
printf '%s\n' "${status}" | grep -Eq '"encrypted"[[:space:]]*:[[:space:]]*true' || {
    printf '%s\n' 'ERROR: target is not SOPS-encrypted' >&2
    exit 1
}
unset status

set +e
mise exec -- sops decrypt --input-type dotenv --output-type dotenv "${target}" |
    awk -F= '$2 == "GENERATE" || $2 == "CHANGE_ME" { found = 1 } END { exit found ? 42 : 0 }'
pipeline_status=("${PIPESTATUS[@]}")
set -e
if ((pipeline_status[0] != 0)); then
    printf '%s\n' 'ERROR: target cannot be decrypted' >&2
    exit 1
fi
if ((pipeline_status[1] == 42)); then
    printf '%s\n' 'ERROR: unresolved secret sentinel' >&2
    exit 1
fi
if ((pipeline_status[1] != 0)); then
    printf '%s\n' 'ERROR: sentinel validation failed' >&2
    exit 1
fi
unset pipeline_status
```

## Windows PowerShell (Git Bash / mise) Invocation

`mise exec -- sops` invoked from within Git Bash on Windows has a known
interaction issue. The documented workaround runs from the **repository
root**: resolve the `sops` executable path once in PowerShell, export it as
`SOPS_BIN` so `scripts/sops-common.sh` invokes it directly instead of going
through `mise exec`, then run the bash scripts through Git Bash as usual and
clean up the environment afterwards. Every placeholder below (`<app>`,
`VARIABLE`, `BYTE_COUNT`, `REQUIRED_VAR`, `<vault>`, `<item>`, `<field>`) is a
placeholder, not a literal production reference:

```powershell
$env:SOPS_BIN = mise which sops
$env:SOPS_AGE_KEY_CMD = 'op read "op://<vault>/<item>/<field>"'
try {
    bash scripts/generate-sops-secrets.sh services/<app>/secret.sops.env VARIABLE=BYTE_COUNT
    bash scripts/validate-sops-secrets.sh services/<app>/secret.sops.env REQUIRED_VAR
} finally {
    Remove-Item Env:SOPS_BIN,Env:SOPS_AGE_KEY_CMD -ErrorAction SilentlyContinue
}
```

Assumptions and rules for this invocation:

- Run it from the repository root — the `services/<app>/...` relative paths depend on it.
- 1Password Desktop must already be unlocked, with CLI integration enabled and the account authenticated, exactly as in [Preferred 1Password Setup](#preferred-1password-setup).
- Never print or execute `$env:SOPS_AGE_KEY_CMD`'s value yourself — it is only ever read by SOPS itself, same as the Hard Safety Rules above.
- `SOPS_BIN` is a non-secret executable path — `mise which sops` only resolves a filesystem location, so setting/printing this specific variable does not expose a secret. Do not repurpose `SOPS_BIN` to carry anything else.
- Raw Windows paths (including ones containing spaces, e.g. under `C:\Users\<name>\...`) are safely quoted by `scripts/sops-common.sh`'s `run_sops` helper when it invokes `${SOPS_BIN}` directly — do not manually quote or re-escape the path yourself.
- Always remove both environment variables in a `finally` block (or equivalent) once the scripts finish, so a later shell in the same session does not silently keep using an overridden `SOPS_BIN`/`SOPS_AGE_KEY_CMD`.

## Troubleshooting

- **`op` unavailable:** Install the 1Password CLI and verify `command -v op` succeeds.
- **`op` unauthenticated or nonzero:** Ask the user to unlock 1Password Desktop and enable CLI integration. Before retrying `op whoami >/dev/null` or any helper, show the new exact retry plan and wait for the user to confirm readiness.
- **No standalone identity line:** Store one supported Age identity in the referenced field.
- **One comment-prefixed flattened line:** Store only the `AGE-SECRET-KEY-...` value or restore the Secure Note's real newlines.
- **SOPS cannot decrypt:** Confirm the selected identity matches a recipient on the target before editing or generating.
- **Generation is a no-op:** The requested values are already populated; this is expected and must not rewrite the encrypted file.
- **`mise exec -- sops` misbehaves under Git Bash on Windows:** Use the [Windows PowerShell invocation](#windows-powershell-git-bash-mise-invocation) above to set `SOPS_BIN` and bypass `mise exec` for that session.
- **"SOPS_BIN does not exist" / "is not executable" / "command not found on PATH":** The configured `SOPS_BIN` value is invalid — re-resolve it (e.g. `mise which sops` in PowerShell) and re-export it; a path-like value must point at an existing, executable regular file, and a bare command name must resolve via `command -v`.
- **Validator reports a missing required variable:** The variable name was not found in the decrypted dotenv output — check for a typo in the `REQUIRED_VAR` argument or confirm the variable actually exists in the target file (e.g. via `sops edit`).
- **Validator reports an unresolved sentinel:** Some variable in the file is still exactly `GENERATE` or `CHANGE_ME` — run `scripts/generate-sops-secrets.sh` for `GENERATE` sentinels, or `sops edit` to fill in a `CHANGE_ME` value manually.

## Disposable-Key Test Pattern

Integration tests generate a fresh temporary Age identity, derive its recipient, encrypt a temporary fixture, expose the identity through a fake offline `op` executable, run the generator, decrypt and verify the result, and rerun to prove no-op idempotency. Failure tests compare the encrypted target's SHA-256 before and after and assert that no `*.generated.*` files remain. No production key or network access is used.
