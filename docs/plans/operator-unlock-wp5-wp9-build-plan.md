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
      a requirement. Public mode uses the install's local CA, as LAN mode does
      (amended by decision 76). **If the
      IP is lost, the sandbox is lost**: the name changes, every passkey stops
      working, and the way back is a rebuild with new passkeys. The recovery
      package restores only and doesn't enroll a passkey (decision 79). dmf-init,
      the console and the sandbox documentation say this plainly, at install
      and before any change of hosting.
51. **A name-constrained private CA that the console and the page share**
    (amended by decisions 58 and 76). dmf-init creates the CA on the
    administrator's workstation at install. The CA may sign only the install's
    own names. The sandbox lane has one CA, which the console and the page
    share. Its key is in dmf-init's store for the env, in the recovery package,
    and, by decision 58, on the node, where the certificate manager renews
    both certificates. The original rule kept the key off the node; decision
    58 reverses that. Public mode uses the same CA (decision 76). Each
    administrator device either taps through the certificate warning or
    installs and trusts the CA once, at enrollment, from the workstation
    (decision 76; see "Trusting the certificate authority"). The CA install
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
      starts the page there first, then restores, with a certificate that it
      issues from the CA key in the package (decision 76). If the IP is gone,
      decision 50 applies.

    The CA key lets its holder impersonate the page. That is less than the
    package already gives its holder (the recovery keys and the seal key), but
    it outlives a key rotation, so the CA is reissued when the package or the
    workstation store is compromised (see "Trusting the certificate
    authority"). This applies in both modes, because each has a CA.
55. **Executor and revoker adjustments** (amended by decisions 83, 87 to 89,
    91 and 92; details left to the orchestrator):
    - A new install never attaches the `generate-root` policy to `ops-admin`,
      so the password and the recovery keys aren't a second path to a root
      token (decisions 91 and 93).
    - The executor doesn't use the generated root token for the change. It
      creates one scoped, use-limited orphan token that lives 15 minutes at
      most, and it revokes the generated root token before the first write
      (decision 83).
    - The standing revoker runs as a Deployment that scans every 60 seconds
      (decision 87). It also scans for tokens with the root policy whose
      accessor isn't recorded, and revokes them. This closes the one crash
      window that the operator unseal plan leaves open. It also revokes a
      break-glass root token on its next run, which is intended: in steady
      state, no root token outlives its approval. The installer's initial token
      is revoked at the end of the install, before the revoker starts
      (decision 90). The revoker reads the audit record through a read-only
      mount (decision 88). If it can't read the record, it treats no accessor
      as recorded, revokes every root-policy token older than the grace period,
      and raises an alert (decision 89). It measures the grace period from the token's creation
      time on the server (decision 92). Decisions 65 to 69 set the grace period
      and the scan.
    - These identities amend ADR-0051 rule 3. The executor may start a root
      token request and finish it only with recovery keys from an approved
      session. The revoker may list, look up, and revoke tokens by accessor.
      The amendment is accepted on RFC Discussion #907, with decisions 83, 91
      and 93 applied in dmfdeploy/dmfdeploy#944.
56. **Later, a public certificate.** A later option, outside this plan, lets an
    engineer with their own domain use a certificate from a public ACME
    certificate authority through their DNS, which removes the CA install.
    That is ADR-0040's own-domain tier.

## Decisions of 2026-11-18

The operator made these decisions after a review of this plan against the
sandbox lane's goal. They are final. The
[decision record](https://github.com/dmfdeploy/dmfdeploy/issues/864#issuecomment-6973603471)
has the full text.

**Certificates and names**

57. **Withdrawn by decision 74.** **Public mode uses a publicly trusted certificate** from an ACME issuer
    for its IP-based name. The private CA protects nothing there, and dropping
    it removes a device step. The page answers the ACME challenge path even
    while no approval is pending. This amends decisions 50 and 51 for public
    mode. It needs an amendment of ADR-0040, through an RFC first.
58. **One CA for the console and the page in the sandbox lane.** Each install
    has one name-constrained CA, and each device installs it once (amended by
    decision 76: a device that taps through installs nothing). Its key
    stays on the node, where the certificate manager renews both
    certificates, and a copy goes into the recovery package for the restore
    certificate (decision 54). This amends decision 51's "key off the node":
    the off-node key protected little where root on the node holds everything.
59. **The page certificate lasts as long as the CA.** A user-installed CA
    isn't held to the short lifetimes that browsers apply to public CAs, so
    renewal never becomes a recurring task.
60. **Click-through doesn't replace the CA install.** Browsers refuse passkeys
    on a page with a certificate error, as ADR-0040 records. A short test on
    the iPad confirms this for its browser. (Amended by decision 76 and
    corrected by decision 78: browsers built on WebKit accept passkeys after a
    tap-through.)
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

65. **The callers of `ops-admin`'s generate-root policy move or retire**
    (amended by decisions 91 and 93: they retire outright). The
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
68. **The revoker's grace period is 5 minutes, and it scans every minute**
    (amended by decision 92: the server's creation time starts the grace period).
    The executor writes an intent entry before it finishes a root token
    request. The revoker revokes an unrecorded root token when no intent is
    open or the token is older than the grace period, so a token left by a
    crash lives 6 minutes at most.
69. **The installer's initial root token is the one exception** (amended by
    decision 90: every install step uses it) to the rule
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

## Decisions of 2026-11-18, second set

These follow a device test of passkeys on pages with certificate errors, and a
review of a project-run name service. The
[decision record](https://github.com/dmfdeploy/dmfdeploy/issues/864#issuecomment-6976610389)
has the full text and the test results. Numbering continues from decision 73.

74. **Decision 57 is withdrawn.** A public certificate on a name under a public
    wildcard DNS service can't be relied on. The service's domain isn't on the
    Public Suffix List, so all its users share one certificate budget, which
    runs out. ADR-0040's archive recorded the same gap on 2026-06-08.
75. **The sandbox is an unsafe, ephemeral learning environment.** It
    demonstrates the approval workflow and protects nothing. The
    documentation, dmf-init and the console say so plainly.
76. **One local CA per install issues the certificates for the console and the
    page, in both modes.** A device either taps through the warning (browsers
    built on WebKit) or installs the CA once (browsers built on Chromium, and
    any browser that refuses). The documentation leads with the tap-through
    path. When the page gets the error "WebAuthn is not supported on sites
    with TLS certificate errors", it switches to guided CA install steps with a
    QR code. This amends decisions 50, 51, 58, and 60.
77. **Project-run sandbox names stay deferred.** The refined design, and the
    gates that must pass before anyone builds it, go into ADR-0040 through an
    RFC.
78. **ADR-0040's statement that tapping through a certificate warning can't
    work with passkeys is corrected.** It holds for browsers built on
    Chromium. Browsers built on WebKit allow it. The same RFC carries the
    correction.

## Decisions of 2026-11-18, third set

These follow a review of WP6, the per-passkey encrypted copy and enrollment,
against decision 75. The
[decision record](https://github.com/dmfdeploy/dmfdeploy/issues/864#issuecomment-6977341381)
has the full text. Numbering continues from decision 78. Long-lived sites keep
the WP6 text in the operator unseal plan as it stands.

79. **The recovery package restores, and that's all it does in the sandbox
    lane.** It doesn't enroll a passkey or approve an operation. Losing every
    passkey means a rebuild, as decision 64 says. This settles the conflict
    with decisions 32 and 45, and closes open point 2.
80. **One passkey finishes a sandbox install.** dmf-init and the console keep
    recommending a second passkey from a different sync account until one is
    enrolled. The documentation says that losing a lone passkey means a
    rebuild. This amends decision 26 for the sandbox lane.
81. **Removing a passkey deletes its credential and its copy, and rotates no
    keys, in the sandbox lane.** The removal record states the limit: the
    removed device has seen the recovery keys during earlier approvals. This
    amends decision 17 for the sandbox lane.

The design details are in the WP6 section of the operator unseal plan.

## Decisions of 2026-11-18, fourth set

Numbering continues from decision 81. The
[decision record](https://github.com/dmfdeploy/dmfdeploy/issues/864#issuecomment-6980461877)
has the full text.

82. **In LAN mode, only the approval page moves to `.local`.** The page is
    served at `dmf-<install-id>.local`. The console and the other apps keep
    the install's base domain. The install's local CA is constrained to that
    base domain and the page's name. Moving every app to `.local` stays out of
    slice C, because every route and OIDC redirect would change shape.

## Decisions of 2026-11-18, fifth set

These follow a scout of dmf-infra and dmf-env for the executor, the revoker, and
the catalogue. Numbering continues from decision 82. The
[decision record](https://github.com/dmfdeploy/dmfdeploy/issues/864#issuecomment-6985438079)
has decisions 83 to 92, and a
[later comment](https://github.com/dmfdeploy/dmfdeploy/issues/864#issuecomment-6985525581)
has decision 93.

83. **The executor mints a scoped, use-limited, short-lived token.** From the
    generated root token, it creates one orphan token with only the catalogue
    entry's pinned policy, a use limit equal to the number of requests that
    entry declares, and a lifetime of 15 minutes at most. It revokes the
    generated root token before the first write. OpenBao revokes the scoped
    token after its last use. This narrows the ADR-0051 amendment text.
84. **In slice B the executor is an identity only.** Its Kubernetes auth role,
    ServiceAccount, policy, and network rule exist, with no workload, because
    no image exists until slice D builds one.
85. **The revoker is a small standard-library script** mounted from a
    ConfigMap, on the landing page's pattern.
86. **dmf-infra holds the catalogue:** one data file plus the pinned policy
    files, rendered into a ConfigMap that the approval service reads in slice D.
87. **The revoker runs as a Deployment that scans every 60 seconds.** A CronJob
    can delay or skip runs, and a stuck run would block the next ones.
88. **The revoker reads the audit record through a read-only mount** of the
    executor's volume.
89. **If the record can't be read, the revoker revokes every unrecorded root
    token older than the grace period and raises an alert.** The executor can't
    mint while the record is broken, because its gate refuses. (Clarified on
    2026-11-18: with the record unreadable, no accessor counts as recorded, so
    the revoker revokes every token with the root policy that is older than
    the grace period. A failure of the revoker's own read or mount therefore
    fails closed.)
90. **Everything during install runs with the installer's initial token,** which
    the installer revokes at the end, before the revoker starts. This widens
    decision 69 to the rotation play and the secret seeding at install.
91. **The new model applies to new installs.** The installer never attaches the
    `generate-root` policy to `ops-admin`. Existing sandboxes keep the old
    model until they're rebuilt, so no live removal step is built. (Amended by
    decision 93: no environment keeps the old model, and environments
    installed before slice B are rebuilt.)
92. **The identity verifier checks an allowlist of login methods** (userpass,
    Kubernetes, AppRole, token) and every role, user, token role, identity
    entity, and group under them. **The revoker measures the grace period from
    the token's creation time on the server;** the intent entry only decides
    whether a request is still open.
93. **No existing environment needs a migration path.** The live sandbox can be
    reset completely, so no environment keeps the old model, and nothing is
    built to carry an installed environment across. The old callers retire
    outright where slice B replaces them. Environments installed before slice B
    are rebuilt.

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
check is the browser itself. On a wrong address, a different name, it doesn't
offer the passkey at all, because a passkey binds to its name. A spoofed page
under the right name is refused only on devices that installed the CA. A device
that tapped through the certificate warning offers the passkey there too (see
"Trusting the certificate authority"), which the sandbox accepts under
decision 75. If a device has no passkey for the address, the page says so and
names the expected address, so nobody enrolls again by mistake.

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
  at install, a new passkey needs approval by an enrolled one. In the sandbox
  lane the recovery package restores only (decision 79). No passkey approves
  its own removal
  (decision 45).
- **The page's certificate stays valid.** Its lifetime equals the CA's
  (decision 59), and the certificate manager renews it on the node. The console warns 30 days before expiry.
  The check-in and approvals keep working until the certificate expires. The
  node holds the certificate and its key as a plain Kubernetes Secret; the
  service needs no ExternalSecret, no OpenBao, and no console to start. It
  terminates its own TLS, so no other component sees the session traffic.

## Public mode

Public mode is weaker than LAN mode, and the plan says so:

- The page answers only while an approval is pending. It returns 404 at every
  other path and time.
- Rate limits and the failed-attempt counter apply, and the console and
  dmf-init warn that this sandbox approves over the public internet.
- The page serves a certificate from the install's local CA, as in LAN mode
  (decision 76). Devices tap through the warning (browsers built on WebKit) or
  install the CA. A device that taps through accepts any certificate, so the
  private CA pins nothing against someone who controls the IP or the wildcard
  DNS answer for it. Public mode still relies on the fixed IP staying the
  operator's and on the wildcard DNS service.

## Trusting the certificate authority

The CA install is the fallback, and tap-through is the default. A device takes one of two
paths (decision 76):

- **Tap through, for browsers built on WebKit.** The administrator taps through
  the certificate warning, and the browser then accepts passkeys on the page.
  On iPadOS, the page loads only when you go back and reload it after tapping the "visit this website" link. The
  warning returns after a browser restart, so it is routine.
- **Install the CA, for browsers built on Chromium.** These browsers refuse
  passkeys on a page with a certificate error. When the page gets the error
  `WebAuthn is not supported on sites with TLS certificate errors`, it offers
  the guided CA install.

After a tap-through, the browser no longer refuses a spoofed `.local` page, so
an attacker on the LAN could imitate the page. The plan accepts this, because
the sandbox is an unsafe, ephemeral learning environment (decision 75).

- **One CA install covers the console and the page.** The CA exists in both
  modes (decisions 58 and 76). Its key is on the node, so the certificate
  manager renews both certificates there, and a copy is in the recovery
  package.
- **The CA comes from the workstation.** dmf-init serves the CA
  download for enrollment from the workstation and shows the CA's fingerprint
  there; the console shows the fingerprint too. The administrator compares it
  with the fingerprint in the device's certificate details. The enrollment
  instructions show where to find it on each platform. The administrator picks the platform, because the browser's user
  agent reports a Mac on an iPad.
- **After the CA is trusted, a spoofed `.local` name can't approve.** This
  holds only for devices that installed the CA. Another device on the LAN can
  claim the name, but it can't present a certificate from the CA. The browser
  refuses the page and doesn't offer the passkey. A spoofed name can block
  approvals; it can't approve or capture key material.
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
| Attacker on the LAN squatting the `.local` name | On devices with the CA installed, the browser refuses the page. On tap-through devices, nothing: an attacker can imitate the page and capture key material during an approval | Yes, under decision 75 (unsafe, ephemeral learning environment) |
| Passkey sync-account takeover | A second passkey in another sync account, which the sandbox recommends but doesn't require (decisions 40 and 80); LAN mode is private | Yes. With one passkey, a takeover of its sync account gives the attacker an approver. In public mode the page is reachable, so this is the largest residual risk there |
| Stolen phone with a known passcode | Device user verification | Yes, as decision 8 accepts |
| Loss of the IP or of the wildcard DNS service (public mode) | None beyond the requirement | Yes, "lose the IP, lose the sandbox" |
| Someone who controls the IP or the wildcard DNS answer (public mode) | None for tap-through devices, which accept any certificate; the CA pins nothing against them | Yes (decisions 75 and 76) |

## Device test, 2026-11-17

A throwaway page at `https://dmf-devtest.local:18443`, behind a
name-constrained test CA, ran on an iPad with iPadOS 27, with a VPN connected.
Chrome on iPadOS uses the same engine as Safari, so its row isn't independent
evidence for Chrome on Android or on a desktop.

| Browser | Name resolves | CA install | Enroll with PRF and user verification | PRF output stable | Decrypt round trip |
|---|---|---|---|---|---|
| Safari | Yes | Yes, through a profile, then the Certificate Trust Settings switch | Yes, synced passkey | Yes, also after a browser restart | Yes. Not rechecked after the restart, because the page's storage was cleared |
| Chrome | Yes | Uses the same system trust store | Yes, synced passkey | Yes | Yes |

## Device test, 2026-11-18

A throwaway page behind a local CA served one variant per certificate error
(self-signed, unknown issuer, and others), each checked to fail for its
intended reason only.

| Device and browser | Result |
|---|---|
| iPadOS, Safari | Passkey with PRF and user verification works after a tap-through (go back and reload). The warning returns after a restart. |
| iPadOS, Chrome | Works after a tap-through. It runs on WebKit there. |
| macOS, Safari | Works after a tap-through. |
| macOS, Chrome | Refuses: "WebAuthn is not supported on sites with TLS certificate errors." |
| Chrome and the Samsung browser on Android | Refuse with the same error. `.local` names resolve. |
| Android, Chrome, CA installed | No warning, and the passkey prompt appears. The enrollment wasn't completed, because the device was borrowed. |

**Before the sandbox rollout**, these need a result:

- an address change of the node: the passkey still approves, and the name is
  still announced;
- an enrollment on Android with the CA installed, on a device with its owner's
  account;
- a device with no VPN;
- an iPhone, which is optional because it is expected to match the iPad;
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

Each part of a slice is one pull request per repository, so a slice with several parts can have more than one in a repository (slice C has two in dmf-infra), and each one ships switched
off until the slices it depends on are in.

| Slice | What it delivers | Done when | Depends on |
|---|---|---|---|
| A. Audit record | Audit module done: dmfdeploy/dmf-init#55, merged 2026-11-18. In dmf-init: a stdlib-only audit module with a chained, numbered, append-only record, on a node volume that only the executor writes to. Retention is 13 months or 64 MiB, whichever comes first: it trims whole segments and keeps the hash of the last trimmed entry. Tamper and gap detection. A gate refuses a root token when its record can't be written, and a full record never blocks an unseal. Intent entries for the revoker. The installer's first entry records its initial root token (decision 69). The failed-attempt counter lives on the public tier's own small volume. The slim second build target of decision 73 moves to slice D, where the approval service first needs an image. | The retention (13 months, 64 MiB) and the overflow behavior are recorded and tested, including a full record that doesn't block an unseal and a flood of failed attempts that doesn't trim authenticated entries. | None |
| C. Modes, name, and CA | Done: dmfdeploy/dmf-env#43, dmfdeploy/dmf-init#56, dmfdeploy/dmf-infra#155 and #156, dmfdeploy/dmf-cms#221, merged 2026-11-18. Four parts in five pull requests (C3 has two) in order, listed below the table. In both modes the install gets one CA, made on the workstation and shared by the console and the page. The CA lasts 730 days (two years). The page detects the Chromium certificate error and shows the guided CA install with a QR code. The cluster's own self-signed CA is replaced for new installs only. | A fresh install in each mode serves a valid certificate under the right name; in LAN mode the fingerprint matches in both places and one CA install covers the console and the page. | The address-change device test (decision 61) |
| B. Executor identity and catalogue | Seven steps, B0 to B6, listed below the table. They take eight pull requests, because B5 has one in dmf-infra and one in dmf-env. The steps build the executor's identity with no workload, the catalogue and its pinned policies, the standing revoker, the identity verifier, the install path, and a dry run against the fake OpenBao. The ADR-0051 amendment is accepted on #907, and the ADR text is in dmfdeploy/dmfdeploy#944. | The executor alone can't finish a root token request. After the install, no path to a root token outside the executor remains in dmf-infra or dmf-env. Drift is refused before the mint; recovery works after a crash at each step; the scan revokes an unrecorded root token, doesn't race an in-flight mint, and a token left by a crash lives 6 minutes at most. | None. It no longer waits for the amendment |
| D. Page, session, and enrollment | In dmf-init: the public tier, and the slim second build target of decision 73 that the approval service runs from. Sessions are single use and bound to one catalogue entry and its parameters. WebAuthn uses user verification and the relying party ID. The page shows the short code and the catalogue text. Enrollment and removal need an enrolled passkey. The encrypted copy is released only after a verified assertion (decision 42). Rate limits, and a 404 when nothing is pending. It starts with a fixture credential and a fixture copy, so it doesn't wait for WP6. The real encrypted copy then follows the WP6 sandbox design in the operator unseal plan: a key pair from the PRF output, and the enrolled device makes the new copy. | WP5's negative tests; the rate-limit and 404 tests; an enrollment that another LAN device can't take over; a console session that can't add or remove a passkey; a compromised-console test in which the page shows the real operation. | A, B (the catalogue), C. The real encrypted copy depends on the WP6 key-pair device test (decision 37) |
| E. Executor run | In dmf-init: the executor tier, with login, the per-session key, generate-root with the recovery keys, the recorded accessor, the drift checks, the scoped mint, the revokes, and the audit lines. | WP5's sandbox-lane run and its injected-failure tests; the public tier's server side never holds the recovery keys in clear; the page refuses an executor key that isn't signed by the executor. | A, B, D |

The order is A first, then B, and C once the device tests of decision 61 pass, then D and E. Slice B no longer waits for the ADR-0051 amendment.

Slice C is four parts, C0 to C3, in five pull requests (C3 has one in dmf-cms and one in dmf-infra), in this order:

1. **C0, dmf-env:** the network mode and the page's name
   ([dmfdeploy/dmf-env#43](https://github.com/dmfdeploy/dmf-env/issues/43)).
2. **C1, dmf-init:** the mode question, the name-constrained CA made on the
   workstation and kept with the env, the CA download and fingerprint, and the
   warnings.
3. **C2, dmf-infra:** import the CA, make the leaf certificates under the right
   names and renew them, and announce the page's `.local` name.
4. **C3, dmf-cms:** the fingerprint and the warnings in the console.

Slice B is seven steps in eight pull requests. Every step is in dmf-infra, and
B5 also has one in dmf-env. Start with step B0. Steps B1 and B2
can run in parallel. Steps B3 to B6 follow in order.

0. **B0, test fake:** extend the OpenBao fake with a token store (policies,
   orphan flag, use limit, creation time, lifetime, accessors), the token and
   accessor calls, Kubernetes login and role reads, generate-root enforcement
   per token, and the reads the verifier needs. The other steps depend on it.
1. **B1, executor identity:** the ServiceAccount, the Kubernetes auth role with
   only the `generate-root` policy and a short lifetime, its NetworkPolicy
   (cluster-internal callers only), and the allow rule on OpenBao ingress. No
   workload (decision 84).
2. **B2, catalogue and pinned policies:** the data file, with each entry's name,
   consequence text, pinned policy file, SHA-256 digest, parameter schema, and
   request count for the use limit. The first entries are the `ops-admin`
   password rotation and any seeding entries. The openbao role installs the
   policies, and a ConfigMap carries the catalogue (decision 86). A test checks
   the digests for drift.
3. **B3, revoker:** its ServiceAccount, Kubernetes auth role, and policy, and a
   standard-library scan script in a ConfigMap. A Deployment runs the script
   every 60 seconds (decisions 85 and 87). It reads the audit record through a
   read-only mount (decision 88) and measures the grace period from the token's
   server creation time (decision 92). If it can't read the record, it treats
   no accessor as recorded, revokes every root-policy token older than the
   grace period, and alerts (decision 89). It starts only after the install.
4. **B4, verifier coverage:** the allowlist of login methods and the
   policy-holder check across roles, users, token roles, identity entities, and
   groups (decision 92), plus the live policy digests.
5. **B5, install path and caller retirement:** the installer does every root
   step with its initial token and revokes it at the end (decision 90). It never
   attaches `generate-root` to `ops-admin` (decision 91). The 2.6 preflight
   checks the executor role. The 120 rotation's `ops-admin` path and the
   README procedure retire outright (decision 93). In dmf-env, a second pull
   request retires the temporary root helper and moves its callers in the
   secret bootstrap to the installer's initial token (decisions 90 and 93).
   Slice B isn't done until both pull requests are in.
6. **B6, dry run:** end to end against the fake, including a crash after the
   intent, after the mint, and before the write.

## Audit record design

Slice A is dmfdeploy/dmf-init#55.

- **Format:** the record is JSON Lines in segment files named `segment-NNNNNNNN.jsonl`. Each
  entry has `seq`, `time`, `prev`, `event`, the event's fields, and `hash`. The
  hash is SHA-256 over the canonical JSON without `hash`. No key rests on the
  node.
- **Start:** a new chain begins with a `genesis` entry. A restored node starts
  a new chain whose next entry is `restore`. It links to the old `seq` and
  `hash`, or says `unlinked`.
- **Segment size:** a segment rolls when it reaches 1 MiB, so it ends slightly
  over. It also rolls when a new entry falls in a later UTC month than the
  segment's first entry. The monthly roll lets age trimming run on a quiet
  record that never reaches 1 MiB. Whole segments are the unit of trimming.
- **Retention:** trim the oldest segments while the total exceeds 64 MiB, or
  while the oldest segment's newest entry is older than 13 months (396 days).
  Trimming runs on every roll, so the total can exceed the cap by about one
  segment, and an entry can outlive 13 months by up to a month. The newest
  segment is never trimmed.
- **Anchor:** before deleting a segment, write `anchor.json`, which holds the
  `seq` and `hash` of that segment's last entry, by atomic replace. `verify`
  reports TRIMMED when the first remaining entry's `prev` matches the anchor.
- **Overflow:** a full record trims and keeps accepting writes. It never
  refuses a write for size. If trimming fails, the write still succeeds.
- **Gate:** `require_written` validates the entry, appends it under an
  exclusive file lock, and fsyncs the file (and the directory for a new
  segment). On any failure it rolls back the partial write and raises
  `AuditWriteError`. The executor aborts the root token request on a raise.
  `try_write` is for the unseal path. It never raises, and it counts what it
  drops in memory.
- **Counter:** a separate directory holds a total and a ring of the last 1,000
  attempts (time, source, reason). It has a single owner (a lock at open) and
  is best-effort, with no fsync. It never touches the chain.
- **What a gap or truncation loses:** a GAP means entries or segments are gone,
  and the record can't say what they held. Deleting entries from the end of the
  newest segment is not detectable, because nothing after them refers back. The
  anchor shows only that a trim happened. The chain protects against
  accidents. Root can defeat it.
- **Entry bounds:** a string is at most 1024 characters, including `claimed`
  keys and values and list items. `claimed` has at most 32 keys, and a list has
  at most 16 items. The canonical JSON of an entry as stored is at most 8192
  bytes. In the worst case, a segment rolls at 1 MiB plus at most one entry, so
  the overshoot past the 64 MiB cap is at most one segment. Device-reported
  input can't grow a segment without bound.
- **Interrupted trims:** a trim writes the anchor, then deletes the segment. If
  it stops between the two, the anchor names the last entry of a segment that
  still exists. `verify` accepts this when that entry carries the anchor's
  hash, and reports TAMPER otherwise. The next write, gated or unseal, deletes
  the leftover segment first, so an interrupted trim finishes on the next
  write. This happens only when the whole chain verifies. A damaged segment is
  never deleted as housekeeping, and the gated write then refuses. While the
  overlap lasts, a retained start higher than seq 1 can't be checked against an
  earlier anchor. The window closes at the next write.
- **Gate verifies the whole chain:** before each gated write, `require_written`
  runs `verify` on the retained chain inside the lock. If the result is not OK
  or TRIMMED, it raises `AuditWriteError` that names the status and the first
  bad seq, and it appends nothing until the record is restored or the sandbox
  is rebuilt (decision 66). The cost is one read of the retained record per
  gated write, bounded by the 64 MiB cap, and gated writes are rare. The unseal
  path (`try_write`) skips the check, so a broken record never blocks an
  unseal.
- **Deleted record:** if the anchor exists and every segment is gone, `verify`
  reports GAP and `require_written` refuses to write. No root token can be
  minted until the record is restored or the sandbox is rebuilt (decision 66).
  The unseal path keeps going through `try_write` and counts drops. A trim
  never removes the newest segment, so this state means deletion. An empty
  directory with no anchor is a first install and starts with `genesis`.
- **Unreadable last entry:** if the newest entry can't be parsed,
  `require_written` fails on every call. This fails closed: no root token can
  be minted, while the unseal path keeps going through `try_write` and counts
  drops. This is acceptable for the sandbox lane (decision 66: rebuild).
- **Genesis:** only the chain writes `genesis`. The schema rejects it from
  callers.
- **Not in this slice:** no service, endpoint, volume, or build target. The
  counter's unauthenticated use and the executor-only mount are deployment
  concerns for later slices.

## Changes to other plans and ADRs

- **WP6:** enrollment moves to the page, started by the console, and needs an
  enrolled passkey after the first one.
- **WP6 and decisions 17 and 26:** the operator unseal plan's WP6 gains a
  sandbox-lane design (decisions 79 to 81). Decisions 17 and 26 are amended
  for the sandbox lane.
- **Decision 18, ADR-0052 and WP5:** the private-network limit is amended for
  public mode only (decision 52).
- **Decision 2:** the CA key is on the workstation, in the recovery package, and
  on the node (decision 58, which amends decision 51). Decision 2 was written
  for the portable kit.
- **ADR-0051 rule 3:** amended for the executor and the revoker (decision 55),
  with the details of decisions 65 to 69. The amendment is accepted on #907,
  with decisions 83, 91 and 93 applied in dmfdeploy/dmfdeploy#944.
- **ADR-0040:** amendment through RFC Discussion
  [#938](https://github.com/orgs/dmfdeploy/discussions/938) (decisions 77 and
  78). It defers project-run names with their gates and corrects the
  click-through statement.

## Open points

1. **The WP5 and WP9 design records** that the operator unseal plan names: the
   session message format, the executor's role and bindings, the retention
   period, and how the page keeps the cross-device passkey flow out of
   approvals. Slices A, B, and D record them. WP9: recorded in "Audit record design" (slice A).
2. **The package path for enrollment**: settled by decision 79 for the sandbox
   lane. The package restores only, so a lost IP, or the loss of every
   passkey, means a rebuild.
3. **The device results** listed in the device test section, before the
   sandbox rollout.
4. **The order of the device tests** (decision 61): the address-change test
   runs before slice C.
5. **Console login with the enrolled passkeys** comes later, outside WP5
   (decision 63), tracked in [#936](https://github.com/dmfdeploy/dmfdeploy/issues/936).
6. **Losses mean a rebuild:** losing every enrolled passkey, or the workstation
   with the recovery passphrase (decision 64).
