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
- Never redirect decrypted SOPS output to a plaintext file.
- Never commit plaintext `.env`, key, editor backup, or temporary generated files.
- Keep `secret.sops.env` encrypted before and after every operation.
- Use `scripts/generate-sops-secrets.sh` only for generate-once bootstrap. Existing values are preserved; rotation is manual.
- Never run the generator concurrently against the same file.
- Use only `VARIABLE=BYTE_COUNT` arguments for random values. Do not pass user-supplied credentials or shared values.
- Use disposable Age identities in tests. Never use a production key in CI or test fixtures.

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

Safely validate the reference without printing the key. The check accepts one
X25519, post-quantum, or plugin identity:

```sh
identity_line_count="$(
    set -o pipefail
    /bin/sh -c "${SOPS_AGE_KEY_CMD}" |
        awk '
            { sub(/\r$/, "") }
            /^$/ || /^#/ { next }
            /^AGE-(SECRET-KEY|PLUGIN)-[0-9A-Z-]+$/ { count++; next }
            { invalid = 1 }
            END { if (invalid) exit 1; print count + 0 }
        '
)"
test "${identity_line_count}" -eq 1
unset identity_line_count
```

Valid output contains exactly one complete supported Age identity line. A normal
multiline Age identity file may also contain comment lines. Reject output
flattened into one comment-prefixed line, because the identity is no longer a
standalone parseable line.

Before editing, prove that SOPS can use the configured identity while discarding decrypted output:

```sh
target='services/<app>/secret.sops.env'
mise exec -- sops decrypt --input-type dotenv --output-type dotenv "${target}" >/dev/null
```

`<app>`, `<vault>`, `<item>`, and `<field>` are placeholders, not literal production references.

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

## Safely Review and Edit

Use VS Code as the SOPS editor so plaintext remains only in the editor-managed temporary buffer:

```sh
target='services/<app>/secret.sops.env'
SOPS_EDITOR='code --wait' mise exec -- sops edit "${target}"
```

Replace remaining `GENERATE` sentinels and any required user-supplied or shared values, then save and close the editor so SOPS re-encrypts the file.

For automation, use `sops set --value-stdin` with a correctly JSON-encoded value so the secret does not appear in command arguments or shell history. The generate-once helper uses this pattern. Prefer `sops edit` for human changes rather than constructing a `sops set` command manually.

Validate the result without writing plaintext. `sops filestatus` reports
plaintext files with a successful command exit, so inspect its JSON result
explicitly:

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

## Troubleshooting

- **`op` unavailable:** Install the 1Password CLI and verify `command -v op` succeeds.
- **`op` unauthenticated or nonzero:** Unlock 1Password Desktop, approve CLI integration, and rerun `op whoami >/dev/null`.
- **No standalone private-key line:** Store a valid Age identity file containing exactly one `AGE-SECRET-KEY-1...` line.
- **One comment-prefixed flattened line:** Restore the original multiline identity-file formatting; do not strip its newlines.
- **SOPS cannot decrypt:** Confirm the selected identity matches a recipient on the target before editing or generating.
- **Generation is a no-op:** The requested values are already populated; this is expected and must not rewrite the encrypted file.

## Disposable-Key Test Pattern

Integration tests generate a fresh temporary Age identity, derive its recipient, encrypt a temporary fixture, expose the identity through a fake offline `op` executable, run the generator, decrypt and verify the result, and rerun to prove no-op idempotency. Failure tests compare the encrypted target's SHA-256 before and after and assert that no `*.generated.*` files remain. No production key or network access is used.
