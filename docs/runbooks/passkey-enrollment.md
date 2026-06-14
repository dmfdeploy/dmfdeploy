# DMF Operator Passkey Enrollment

**Status:** Operator-facing runbook. End-to-end procedure for enrolling
the two passkeys required by ADR-0028 D8 for a fresh DMF environment.

**Intent model:**
[ADR-0015 — DMF Console passkey-only](../decisions/0015-dmf-console-passkey-only.md);
[ADR-0028 — Identity and Authority Chain](../decisions/0028-identity-and-authority-chain.md)
(C1 Authentik-as-sole-identity-authority, D8 ≥2 confirmed devices per
human);
[ADR-0010 — `bin/run-playbook.sh` sanctioned ansible entry](../decisions/0010-run-playbook-as-sanctioned-entry.md).

**Audience:** the human operator. Agents may execute steps on your
behalf but should not bypass any step here without recording the
exception in STATUS HUMAN-START.

---

## Why two passkeys, and why two surfaces

ADR-0028 D8 mandates **at least two confirmed WebAuthn devices** per
human, so that loss or destruction of one authenticator does not
lock you out. "Two devices" means two **different authenticators**
(hardware key, iCloud Keychain, Google Password Manager, Windows
Hello, etc.) — not two credentials on the same authenticator. (Most
authenticators enforce per-relying-party-per-username uniqueness, so
re-registering on the same authenticator silently fails anyway. See
"Same-authenticator failure mode" below.)

There are **two enrollment surfaces** on the platform, by design:

| Surface | When | Why |
|---|---|---|
| `dmf-env/bin/get-passkey-enrollment-url.sh <env>` (operator-helper script) | **Passkey #1**, before you have any Authentik session | Reads the bootstrap-passkey invitation from OpenBao, self-heals via `bin/run-playbook.sh` if the cached invitation is stale (ADR-0010). Requires no prior login. |
| DMF Console → Settings page → *Create new device invitation* (browser UI) | **Passkey #2+**, after you've logged in with passkey #1 | Console self-service path (`POST /api/admin/invitations`, sanctioned by [ADR-0015 lines 41-43](../decisions/0015-dmf-console-passkey-only.md)). Mints a per-click invitation via the Authentik REST API. Requires an active session. |

The script does not see the Console's invitations, and the Console
does not see (or update) the OpenBao-cached bootstrap invitation. Each
surface is right for its phase of the bootstrap.

---

## TL;DR

```bash
# Passkey #1 (terminal):
cd "$DMFDEPLOY_UMBRELLA/dmf-env"
bin/get-passkey-enrollment-url.sh <env>          # prints a single-use URL
# Open the URL in a private/incognito window.
# In the browser's authenticator picker, choose Authenticator A
# (e.g. iCloud Keychain / Apple Passwords).

# Passkey #2 (browser):
# 1. Visit the DMF Console: https://console.<env-base-domain>/
# 2. Sign in with passkey #1.
# 3. Go to Settings → "Create new device invitation".
# 4. Open the resulting URL (or scan the QR) on the device that holds
#    Authenticator B (e.g. a YubiKey, an Android phone, a second Mac
#    with a different Apple ID, Windows Hello).
# 5. Complete registration.

# Verify both landed:
bin/get-passkey-enrollment-url.sh <env>
# expected:  "passkey requirement met for user: <you>"
#            "confirmed passkeys: 2/2 (ADR-0028 D8, live)"
#            "no new enrollment URL needed"
```

---

## Step 1 — Passkey #1 via the operator-helper script

The script reads the OpenBao-cached bootstrap invitation; if Authentik
no longer has a live invitation matching the cache (consumed, expired,
wiped), it self-heals by invoking
`playbooks/vertical-security/111-authentik-passkey-ensure.yml` through
`bin/run-playbook.sh` (ADR-0010 sanctioned). You don't need to know
which path it took.

```bash
cd "$DMFDEPLOY_UMBRELLA/dmf-env"
bin/get-passkey-enrollment-url.sh <env>
```

Expected output (fast path — cached invitation is live):

```
env:           <env>
ssh target:    <user>@<control-node>
breakglass:    /path/to/<env>/openbao-keys.json
enrollment_url: https://auth.<env-base-domain>/if/flow/dmf-bootstrap-passkey-enrollment/?itoken=<uuid>
confirmed passkeys: 0/2 (ADR-0028 D8, live)
expires:        <iso-timestamp, 24h out>
```

Expected output (self-heal — playbook log scrolls past, then):

```
…
PLAY RECAP ***
<host>  : ok=45  changed=2  …
enrollment_url: https://auth.<env-base-domain>/if/flow/dmf-bootstrap-passkey-enrollment/?itoken=<new-uuid>
confirmed passkeys: 0/2 (ADR-0028 D8, live)
expires:        …
source:         freshly minted (cached invitation was missing in live Authentik)
```

**Open the URL in a private/incognito browser window** so any
pre-existing session state from another env doesn't bleed in. Pick the
authenticator you've decided will be Authenticator A. **Decide A and
B up front** — see "Choosing two authenticators" below.

Complete the WebAuthn ceremony. The browser may also offer to log you
into the Console; accept it.

---

## Step 2 — Passkey #2 via the Console UI

You are now logged in to the DMF Console as the operator.

1. Click the user menu (top-right) → **Settings**.
2. Find the **Passkey Enrollment** panel.
3. Click **Create new device invitation**.
4. The panel renders a single-use URL and a QR code.
5. **Open the URL on the device that holds Authenticator B**, or scan
   the QR with that device's camera.
   - If Authenticator B is a hardware security key (YubiKey, Solo,
     Token2), open the URL in any browser, plug the key in, choose
     "Use a security key" in the picker, and touch.
   - If Authenticator B is a phone, scan the QR with the phone's
     camera (iOS/Android both render the WebAuthn ceremony natively).
   - If Authenticator B is "this browser's local passkey store"
     (Chrome's Google Password Manager, Brave's, etc.), open the URL
     in **that browser specifically**, and in the picker explicitly
     choose the non-Apple/non-Windows option.

6. Complete the WebAuthn ceremony. The panel will show a success
   state. Verify from the terminal:

   ```bash
   bin/get-passkey-enrollment-url.sh <env>
   # → "passkey requirement met for user: <you>"
   #   "confirmed passkeys: 2/2 (ADR-0028 D8, live)"
   ```

---

## Choosing two authenticators

The point of D8 is **recovery diversity**: if one authenticator is
lost or destroyed, the other still gets you in. Two passkeys on the
same iCloud Keychain do not satisfy this — they're the same key, just
synced across your Apple devices. Likewise two passkeys on the same
Google account, same hardware key, etc.

Pick A and B from **different rows** in this table:

| Row | Authenticator | Typical surfaces |
|---|---|---|
| 1 | iCloud Keychain / Apple Passwords | Safari + macOS/iOS Touch ID/Face ID |
| 2 | Google Password Manager | Chrome on Android / desktop (Google account passkey) |
| 3 | Windows Hello | Edge / Chrome on Windows with PIN/biometric |
| 4 | Hardware security key | YubiKey 5 / 5C / NFC, Solo 2, Token2, etc. — works across all browsers |
| 5 | Mobile passkey store on a different Google/Apple account | "Other device" QR flow |
| 6 | Bitwarden / 1Password (if browser extension supports passkey storage) | Cross-platform |

**Recommended for break-glass-grade**: one platform authenticator
(rows 1-3, whichever your daily-driver OS gives you) plus **one
hardware key** (row 4). The hardware key lives in a physical safe.

---

## Same-authenticator failure mode

If you try to register a second passkey using the **same** authenticator
that holds your first one, this is what you'll see:

- The browser opens the authenticator picker (Touch ID prompt, etc.).
- You authenticate.
- The picker either silently dismisses, or the browser shows
  "You already have a passkey for this site, use that to sign in"
  or a similar message.
- The Authentik flow does **not** complete — no new `WebAuthnDevice`
  row is created in the Authentik DB.
- The invitation is **consumed** if it reached the user_write stage,
  so the URL is now dead.

This is by design: WebAuthn's `excludeCredentials` parameter, populated
from your existing credentials on this user, tells the authenticator
"don't create another credential the same authenticator already holds."
Apple Passwords, Google Password Manager, Windows Hello, and most
others honour this strictly.

Recovery: re-run the script (which will self-heal a fresh invitation)
or click *Create new device invitation* in the Console again, and use
**a different authenticator** for the second attempt.

---

## Troubleshooting

### "Invalid invite / invite not found"

The single-use invitation has been consumed (someone clicked it before
you, or you completed an earlier attempt that consumed it) or it
expired. **Re-run `bin/get-passkey-enrollment-url.sh <env>`** — the
script's self-heal path mints a fresh invitation and refreshes the
OpenBao cache. The first lines of output will say
`source: freshly minted` when this happens.

### Script says `confirmed passkeys: 1/2` after I enrolled twice

Either (a) your second enrollment used the same authenticator as the
first and was silently rejected (see "Same-authenticator failure mode"
above) — fix by using Authenticator B, or (b) the WebAuthn ceremony
was cancelled / the browser tab closed before completion. Re-run the
Console's *Create new device invitation* and retry.

### Console's *Create new device invitation* returns 500/503

The Console hasn't been wired with an Authentik API token. Re-run:

```bash
cd "$DMFDEPLOY_UMBRELLA/dmf-env"
bin/run-playbook.sh <env> ../dmf-infra/k3s-lab-bootstrap/playbooks/696-cms-authentik-api.yml
```

### `error: cached invitation is not live in Authentik (--read-only blocks self-heal)`

You ran the script with `--read-only` and the cached URL was stale.
Run again without `--read-only`.

### `error: operator user '<u>' not found in Authentik`

The bootstrap path hasn't seeded the operator user yet. Run the
authentik playbook:

```bash
bin/run-playbook.sh <env> ../dmf-infra/k3s-lab-bootstrap/playbooks/vertical-security/110-authentik.yml
```

---

## Cross-references

- Script source:
  [`dmf-env/bin/get-passkey-enrollment-url.sh`](https://github.com/dmfdeploy/dmf-env/blob/main/bin/get-passkey-enrollment-url.sh)
- Bootstrap-invitation mint logic:
  [`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/files/ak_passkey_invitation.py`](https://github.com/dmfdeploy/dmf-infra/blob/main/k3s-lab-bootstrap/roles/stack/operator/authentik/files/ak_passkey_invitation.py)
  (single source of truth, used by both the role and the mini-playbook).
- Self-heal mini-playbook:
  [`dmf-infra/k3s-lab-bootstrap/playbooks/vertical-security/111-authentik-passkey-ensure.yml`](https://github.com/dmfdeploy/dmf-infra/blob/main/k3s-lab-bootstrap/playbooks/vertical-security/111-authentik-passkey-ensure.yml)
- Console self-service endpoint:
  [`dmf-cms/src/dmf_cms/main.py`](https://github.com/dmfdeploy/dmf-cms/blob/main/src/dmf_cms/main.py)
  (`POST /api/admin/invitations`) +
  [`dmf-cms/src/dmf_cms/authentik.py`](https://github.com/dmfdeploy/dmf-cms/blob/main/src/dmf_cms/authentik.py)
  (`create_invitation`).
- Policy alignment (this runbook's reasoning):
  [`docs/reviews/DMF Passkey Invitation Policy Alignment Survey 2026-05-28.md`](../reviews/DMF%20Passkey%20Invitation%20Policy%20Alignment%20Survey%202026-05-28.md).
