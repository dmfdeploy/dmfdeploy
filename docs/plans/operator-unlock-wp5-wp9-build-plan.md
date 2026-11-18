---
status: draft
date: 2026-11-18
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/864
---

# Build plan for the sandbox approval page and audit record (WP5 and WP9)

This plan turns WP5 (approval page and session) and WP9 (audit record) of the
[operator unseal plan](operator-unlock-tier2-plan.md) into a build order for the
sandbox lane. That plan holds decisions 1 to 48 and the properties each package
must meet. This plan adds the operator's decisions of 2026-11-17 and 2026-11-18, the design
properties that two reviews asked for, the residual risks, and the slices.

Everything in this plan applies to the **sandbox lane only**. Where it changes
one of decisions 1 to 48, a work package or an ADR, it says so.

## Decisions of 2026-11-17

The operator made these decisions in the session of 2026-11-17, after a scouting
report, a research report on private networks, a device test, and two reviews.

49. **No VPN in the sandbox lane.** A media engineer stands up a sandbox
    without a domain of their own and without installing VPN software on their
    devices.
50. **Two network modes, chosen at install.** dmf-init asks which mode the
    sandbox uses, and the approval page gets a fixed name in each. Every
    passkey binds to that name as its relying party ID.
    - **LAN or air-gapped.** The sandbox announces `dmf-<install-id>.local` on
      the LAN through DNS-SD and mDNS. It needs no public DNS, so it also works
      without internet. The name doesn't depend on the computer's IP address,
      so a passkey is expected to survive an address change. The rollout waits
      for a test that confirms it.
    - **Public, with a fixed IP.** For a VPS. The page is
      `unlock.<ip>.<wildcard-DNS-domain>`, a name from a public wildcard DNS
      service that maps a name to the IP it contains, and a fixed public IP is
      a requirement. Public mode uses a publicly trusted certificate (amended
      by decision 57). **If the
      IP is lost, the sandbox is lost**: the name changes, every passkey stops
      working, and the way back is a rebuild with new passkeys. Recovering
      without a rebuild needs the package path for enrollment, which WP6 has
      yet to design (open point 2). dmf-init,
      the console and the sandbox documentation say this plainly, at install
      and before any change of hosting.
51. **A name-constrained private CA, shared by the console and the page**
    (amended by decisions 57 and 58). dmf-init creates the CA on the
    administrator's workstation at install. The CA may sign only the install's
    own names. The sandbox lane has one CA, which the console and the page
    share. Its key is in dmf-init's store for the env, in the recovery package,
    and, by decision 58, on the node, where the certificate manager renews
    both certificates. The original rule kept the key off the node; decision
    58 reverses that. In public mode there is no private CA (decision 57).
    Each administrator device installs and trusts the CA once, at enrollment,
    from the workstation (see "Trusting the certificate authority"). This
    follows ADR-0040, whose local-CA tier already asks for a one-time CA
    install.
52. **A public page in public mode.** Public mode has no private network, so
    the page is reachable from the internet. This amends decision 18, the
    private-network limit in ADR-0052, and WP5's "reachable only on the private
    network", for public mode only, with the precautions in the public mode section.
    In LAN or air-gapped mode, those hold as written.
53. **Where the code lives.** The code lives in the dmf-init repository.
    dmf-infra deploys the service in the same early layer as the platform
    landing page (playbook 600), on the landing page's pattern, but not in its
    pod. During a restore, dmf-init runs the same code. No new repository is
    created.
54. **The restore certificate.** For a restore with the node gone, dmf-init
    issues a short-lived certificate for the page's name with the CA key from
    its store, or from the package copy of the CA key when the store is gone
    (amended by decision 58). The page answers under that name:
    - in LAN or air-gapped mode, from the workstation, which announces the
      `.local` name itself;
    - in public mode, from a replacement VPS that holds the same IP; dmf-init
      starts the page there first, then restores. The replacement VPS gets a
      public certificate for the name, so this case needs no CA key (decision
      57). If the IP is gone, decision 50 applies.

    The CA key lets its holder impersonate the page. That is less than the
    package already gives its holder (the recovery keys and the seal key), but
    it outlives a key rotation, so the CA is reissued when the package or the
    workstation store is compromised (see "Trusting the certificate
    authority"). This applies to LAN mode, where the CA exists.
55. **Executor and revoker adjustments** (details left to the orchestrator):
    - Once the executor's identity exists, `ops-admin` loses the
      `generate-root` policy, so the password and the recovery keys aren't a
      second path to a root token.
    - The standing revoker also scans for tokens with the root policy whose
      accessor isn't recorded, and revokes them. This closes the one crash
      window that the operator unseal plan leaves open. It also revokes a
      break-glass root token or an install's initial token on its next run,
      which is intended: in steady state, no root token outlives its approval. Decisions 65 to 69
      set the grace period and the scan.
    - These identities amend ADR-0051 rule 3. The executor may start a root
      token request and finish it only with recovery keys from an approved
      session. The revoker may list, look up, and revoke tokens by accessor. The
      amendment goes through RFC Discussion #907 before slice B is built.
56. **Later, a public certificate.** A later option, outside this plan, lets an
    engineer with their own domain use a certificate from a public ACME
    certificate authority through their DNS, which removes the CA install.
    That is ADR-0040's own-domain tier. Decision 57 gives public mode a
    publicly trusted certificate without a domain of the engineer's own.

## Decisions of 2026-11-18

The operator made these decisions after a review of this plan against the
sandbox lane's goal. They are final. The
[decision record](https://github.com/dmfdeploy/dmfdeploy/issues/864#issuecomment-6973603471)
has the full text.

**Certificates and names**

57. **Public mode uses a publicly trusted certificate** from an ACME issuer
    for its IP-based name. The private CA protects nothing there, and dropping
    it removes a device step. The page answers the ACME challenge path even
    while no approval is pending. This amends decisions 50 and 51 for public
    mode. It needs an amendment of ADR-0040, through an RFC first.
58. **One CA for the console and the page in the sandbox lane.** Each install
    has one name-constrained CA, and each device installs it once. Its key
    stays on the node, where the certificate manager renews both
    certificates, and a copy goes into the recovery package for the restore
    certificate (decision 54). This amends decision 51's "key off the node":
    the off-node key protected little where root on the node holds everything.
59. **The page certificate lasts as long as the CA.** A user-installed CA
    isn't held to the short lifetimes that browsers apply to public CAs, so
    renewal never becomes a recurring task.
60. **Click-through doesn't replace the CA install.** Browsers refuse passkeys
    on a page with a certificate error, as ADR-0040 records. A short test on
    the iPad confirms this for its browser.
61. **Order.** The address-change test and the `.local` test on an
    Android-powered device run before slice C, because they can change its
    naming code. Slice A doesn't wait for them.
62. **Public text describes outside services by what they do** and leaves out
    their names. This update applies the rule.

**What the sandbox claims**

63. **Console login with the enrolled passkeys** comes later, outside WP5.
    Until then, console passkeys and approval passkeys stay separate.
64. **Losing every enrolled passkey, or the workstation together with the
    recovery passphrase, means a rebuild,** as losing the IP does in public
    mode. dmf-init says so at install.

**The ADR-0051 amendment (decision 55)**

65. **The callers of `ops-admin`'s generate-root policy move or retire.** The
    credential rotation becomes a catalogue entry. The `dmf-env` temporary
    root helper retires on environments that run the executor. The role
    README's manual procedure points to a rebuild.
66. **A rebuild is the way back when the executor can't run,** in the sandbox
    lane. OpenBao's recovery mode repairs storage and gives no root token.
    Long-lived sites decide separately before they drop the policy from
    `ops-admin`.
67. **The identity verifier checks who holds each policy.** Across every
    enabled auth method and identity group, only the executor holds
    `generate-root`, and only the revoker holds the revoker's policy.
68. **The revoker's grace period is 5 minutes, and it scans every minute.**
    The executor writes an intent entry before it finishes a root token
    request. The revoker revokes an unrecorded root token when no intent is
    open or the token is older than the grace period, so a token left by a
    crash lives 6 minutes at most.
69. **The installer's initial root token is the one exception** to the rule
    that no root token is created unless its audit record is written. It
    exists before the record. The installer revokes it and writes the
    record's first entry, which says so.

**Slice A, the audit record**

70. **The record lives on a node volume that only the executor writes to.**
    The console reads it through the executor.
71. **Retention is 13 months or 64 MiB,** whichever comes first. This covers a
    year of monthly check-ins.
72. **The failed-attempt counter lives on its own small volume,** owned by the
    public tier, so a compromised public tier can't reach the record.
73. **The approval service gets a slim second build target** in the dmf-init
    repository. The audit module uses only the standard library, so both
    images share it.

## How an administrator approves an operation

In steady state the sandbox unseals itself, so approvals are rare: the monthly
check-in (decision 10, a passkey confirmation with no root token), enrolling or
removing a passkey, a restore, and the few changes that need a root token. A
change works like this; a restore is the same, except that dmf-init starts it.

1. **In the console**, the administrator asks for the change and clicks
   **Approve**. The console asks the approval service for a session over the
   cluster-internal address only, authenticated by its Kubernetes service
   account token. The public address never creates sessions.
2. **The console shows** a QR code with the session link, a short code such as
   `4F7-K2Q`, and the address where the approval happens, such as `dmf-ab12.local`.
3. **On the administrator's device**, the QR code opens the approval page; on a
   laptop with its own passkey, a link does. The page shows what will happen,
   in plain words that the approval service writes from its own catalogue of
   approvable operations, for example "Rotates the password of `ops-admin`" or
   "Replaces all data with the snapshot of 2026-11-10." Nothing on the page
   comes from the console. The administrator reads it, checks that the short
   code matches the console's, and confirms with Face ID, a fingerprint, or a
   PIN.
4. **The device decrypts** its copy of the recovery keys and encrypts them
   again to the executor of this one session. The executor carries out the
   change.
5. **The page says "Approved, return to the console"**, and the console shows
   the result and the new audit entry.

The page is separate from the console on purpose:

- A passkey binds to one name, and the page needs a fixed one.
- The page must work when the console, OpenBao or ESO is down.
- Nothing runs without a passkey assertion on the page, so a compromised
  console can't approve on its own. The short code shows only that the console
  and the page refer to the same session. It can't show that the operation is
  harmless, because a compromised console could ask for a harmful one. That is
  why the page states the consequence in its own words, and why the
  administrator reads it.

The page keeps the console's look and a name shown in advance, but the real
check is the browser itself: on a wrong or spoofed address, it doesn't offer
the passkey at all. If a device has no passkey for the address, the page says
so and names the expected address, so nobody enrolls again by mistake.

## Design properties from the reviews

- **Two tiers, and what the split does and doesn't protect.** The service
  runs as two processes with separate identities. The executor holds the
  Kubernetes-auth identity, accepts no traffic from outside the cluster, and
  has a NetworkPolicy to match. The device encrypts the recovery keys to a key
  that the executor makes for each session, and the public tier relays only
  that ciphertext. So the code that parses internet input can't reach the
  executor's identity, and the public tier's server side never handles the
  keys in clear.

  The split doesn't take the public tier out of the trust boundary. The
  public tier serves the page's JavaScript, which runs in the passkey's origin
  and handles the PRF output and the decrypted keys. A compromised public tier
  could serve code that sends them elsewhere, and TLS doesn't protect against
  the server itself. The plan accepts this risk for the sandbox lane and
  narrows it in three ways. The page's code is static, built into the image,
  and served read-only by a small server that answers only plain file
  requests. The session API is separate from it. The executor signs its
  per-session key, so the page refuses a substituted key.
- **A closed catalogue of approvable operations.** The service holds the list:
  each operation's plain-language consequence, its pinned policy and digest,
  and the parameters it accepts. The console can only choose an entry and
  supply parameters that the catalogue validates. Slice B defines it, and
  slice D renders from it.
- **Failed attempts don't fill the audit record.** Unauthenticated failed
  attempts go to a separate counter with its own cap; the chained record keeps
  room for authenticated entries. Rate limits are keyed per session and per
  source address, so an attacker can't lock the administrator out with a
  single global limit.
- **Enrolling and removing passkeys needs an enrolled passkey.** A console
  session alone can never add or remove a passkey. After the first enrollment
  at install, a new passkey needs approval by an enrolled one, or the recovery
  package path once WP6 designs it. No passkey approves its own removal
  (decision 45).
- **The page's certificate stays valid.** Its lifetime equals the CA's
  (decision 59), and the certificate manager renews it on the node. In public
  mode, ACME renewal runs on the node. The console warns 30 days before expiry.
  The check-in and approvals keep working until the certificate expires. The
  node holds the certificate and its key as a plain Kubernetes Secret; the
  service needs no ExternalSecret, no OpenBao, and no console to start. It
  terminates its own TLS, so no other component sees the session traffic.

## Public mode

Public mode is weaker than LAN mode, and the plan says so:

- The page answers only while an approval is pending. It also answers the ACME
  challenge path, and returns 404 at every other path and time (decision 57).
- Rate limits and the failed-attempt counter apply, and the console and
  dmf-init warn that this sandbox approves over the public internet.
- The page serves a publicly trusted certificate from a public ACME
  certificate authority (decision 57). No private CA exists in public mode, and
  devices install nothing. Whoever controls the IP or the wildcard DNS answer
  for it could obtain a certificate for the name. Public mode relies on the
  fixed IP staying the operator's and on the wildcard DNS service.

## Trusting the certificate authority

- **One CA install covers the console and the page.** The CA exists in LAN mode
  (decisions 57 and 58). Its key is on the node, so the certificate manager
  renews both certificates there, and a copy is in the recovery package.
- **The CA comes from the workstation.** dmf-init serves the CA
  download for enrollment from the workstation and shows the CA's fingerprint
  there; the console shows the fingerprint too. The administrator compares it
  with the fingerprint in the device's certificate details. The enrollment
  instructions show where to find it on each platform. The administrator picks the platform, because the browser's user
  agent reports a Mac on an iPad.
- **After the CA is trusted, a spoofed `.local` name can't approve.** Another
  device on the LAN can claim the name, but it can't present a certificate
  from the CA. The browser refuses the page and doesn't offer the passkey. A
  spoofed name can block approvals; it can't approve or capture key material.
- **The CA has a lifetime and a reissue rule.** dmf-init sets the CA's
  lifetime at install. It reissues the CA, and every device trusts the new one,
  when the recovery package or the workstation store is compromised. A lost
  device alone doesn't require it, because devices never hold the CA
  key. The key on the node (decision 58) is inside the accepted local-root
  risk. Decommissioning removes the CA from every device, as WP7 required for a
  kit.

## Residual risks

| Threat | What limits it | Accepted for the sandbox lane |
|---|---|---|
| Root on the node during an approval | The page, the executor and the keys meet on the node | Yes, the lane's accepted local-root risk |
| Compromised workstation (CA key, dmf-init store, package) | It equals the package holder. The CA key is also on the node (decision 58), so root on the node reaches it too | Yes, stated |
| Stolen recovery package with a weak passphrase | The passphrase and its key derivation, which WP6 specifies | Yes, with a passphrase policy |
| Compromised console | Separate page, catalogue text, passkey required | Yes, the administrator must read the page |
| Compromised public tier | Static, read-only page code; signed executor key; no executor identity in the public tier | Yes, a compromise can capture keys during an approval |
| Attacker on the LAN squatting the `.local` name | The CA; the browser refuses the page | Denial of service only |
| Passkey sync-account takeover | Two independent passkeys (decision 40); LAN mode is private | In public mode the page is reachable, so this is the largest residual risk there |
| Stolen phone with a known passcode | Device user verification | Yes, as decision 8 accepts |
| Loss of the IP or of the wildcard DNS service (public mode) | None beyond the requirement | Yes, "lose the IP, lose the sandbox" |

## Device test, 2026-11-17

A throwaway page at `https://dmf-devtest.local:18443`, behind a
name-constrained test CA, ran on an iPad with iPadOS 27, with a VPN connected.
Chrome on iPadOS uses the same engine as Safari, so its row isn't independent
evidence for Chrome on Android or on a desktop.

| Browser | Name resolves | CA install | Enroll with PRF and user verification | PRF output stable | Decrypt round trip |
|---|---|---|---|---|---|
| Safari | Yes | Yes, through a profile, then the Certificate Trust Settings switch | Yes, synced passkey | Yes, also after a browser restart | Yes. Not rechecked after the restart, because the page's storage was cleared |
| Chrome | Yes | Uses the same system trust store | Yes, synced passkey | Yes | Yes |

**Before the sandbox rollout**, these need a result:

- an address change of the node: the passkey still approves, and the name is
  still announced;
- a device with no VPN; an Android-powered device, where `.local` resolution is
  the main doubt; an iPhone; the Mac;
- the `.local` announcer on a Linux k3s node, and from dmf-init on the
  workstation, including in a container;
- a certificate from another CA, and a certificate from this CA for a name
  outside its constraint, which the browser must both refuse;
- a passkey assertion without user verification, which must be refused
  (decision 44);
- a restore with the real recovery package and an enrolled passkey, in both
  modes;
- a session created through the public address in public mode, which the
  service must refuse.

## Slices

Each slice is one pull request per repository, and each one ships switched
off until the slices it depends on are in.

| Slice | What it delivers | Done when | Depends on |
|---|---|---|---|
| A. Audit record | In dmf-init: a stdlib-only audit module with a chained, numbered, append-only record, on a node volume that only the executor writes to. Retention is 13 months or 64 MiB, whichever comes first: it trims whole segments and keeps the hash of the last trimmed entry. Tamper and gap detection. A gate refuses a root token when its record can't be written, and a full record never blocks an unseal. Intent entries for the revoker. The installer's first entry records its initial root token (decision 69). The failed-attempt counter lives on the public tier's own small volume. The slim second build target (decisions 68 to 73). | The retention (13 months, 64 MiB) and the overflow behavior are recorded and tested, including a full record that doesn't block an unseal and a flood of failed attempts that doesn't trim authenticated entries. | None |
| C. Modes, name, and CA | dmf-init asks for the mode. In LAN mode it creates one CA on the workstation, shared by the console and the page, puts the key on the node and in the package, and serves the CA download. The certificate manager renews both certificates. In public mode there is no private CA: the page gets a public ACME certificate and answers the challenge path. dmf-infra announces the `.local` name in LAN mode. The console shows the fingerprint and the public-mode warning. | A fresh install in each mode serves a valid certificate under the right name; in LAN mode the fingerprint matches in both places and one CA install covers the console and the page. | The address-change and Android `.local` device tests (decision 61) |
| B. Executor identity and catalogue | In dmf-infra: the executor's Kubernetes-auth role and ServiceAccount, its narrow policy, its NetworkPolicy, the standing revoker with a 5-minute grace period and a scan every minute, and the catalogue's pinned per-change policies with their digests. The identity verifier checks every auth method and identity group for who holds each policy. The callers of `ops-admin`'s generate-root policy move or retire (decisions 65 to 69). A dry run against the fake OpenBao. | The executor alone can't finish a root token request; drift is refused before the mint; recovery works after a crash at each step; the scan revokes an unrecorded root token, doesn't race an in-flight mint, and a token left by a crash lives 6 minutes at most. | The ADR-0051 amendment, before it's built |
| D. Page, session, and enrollment | In dmf-init: the public tier. Sessions are single use and bound to one catalogue entry and its parameters. WebAuthn uses user verification and the relying party ID. The page shows the short code and the catalogue text. Enrollment and removal need an enrolled passkey. The encrypted copy is released only after a verified assertion (decision 42). Rate limits, and a 404 when nothing is pending. It starts with a fixture credential and a fixture copy, so it doesn't wait for WP6. | WP5's negative tests; the rate-limit and 404 tests; an enrollment that another LAN device can't take over; a console session that can't add or remove a passkey; a compromised-console test in which the page shows the real operation. | A, B (the catalogue), C. The real encrypted copy waits for the WP6 design (decision 37) |
| E. Executor run | In dmf-init: the executor tier, with login, the per-session key, generate-root with the recovery keys, the recorded accessor, the drift checks, the scoped mint, the revokes, and the audit lines. | WP5's sandbox-lane run and its injected-failure tests; the public tier's server side never holds the recovery keys in clear; the page refuses an executor key that isn't signed by the executor. | A, B, D |

The order is A first, then B, and C once the device tests of decision 61 pass, then D and E.

## Changes to other plans and ADRs

- **WP6:** enrollment moves to the page, started by the console, and needs an
  enrolled passkey after the first one.
- **Decision 18, ADR-0052 and WP5:** the private-network limit is amended for
  public mode only (decision 52).
- **Decision 2:** the CA key is on the workstation, in the recovery package, and
  on the node (decision 58, which amends decision 51). Decision 2 was written
  for the portable kit.
- **ADR-0051 rule 3:** amended for the executor and the revoker (decision 55),
  with the details of decisions 65 to 69.
- **ADR-0040:** amended for public mode's publicly trusted certificate
  (decision 57), through an RFC first.

## Open points

1. **The WP5 and WP9 design records** that the operator unseal plan names: the
   session message format, the executor's role and bindings, the retention
   period, and how the page keeps the cross-device passkey flow out of
   approvals. Slices A, B, and D record them.
2. **The package path for enrollment**, which the operator unseal plan lists as
   open, is needed before public mode can recover from a lost IP without a
   rebuild.
3. **The device results** listed in the device test section, before the
   sandbox rollout.
4. **The order of the device tests** (decision 61): the address-change test and
   the Android `.local` test run before slice C.
5. **Console login with the enrolled passkeys** comes later, outside WP5
   (decision 63), tracked in [#936](https://github.com/dmfdeploy/dmfdeploy/issues/936).
6. **Losses mean a rebuild:** losing every enrolled passkey, or the workstation
   with the recovery passphrase (decision 64).
