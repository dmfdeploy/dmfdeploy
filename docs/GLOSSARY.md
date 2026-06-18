# Glossary

These are the project's own coined terms — the ones an outsider can't google.
Industry vocabulary (NMOS, SMPTE ST 2110, PTP, …) is intentionally out of
scope; if you don't know those, the [EBU DMF Reference Architecture](https://tech.ebu.ch/)
is the entry point.

### age key

An [age](https://age-encryption.org/) asymmetric keypair used to encrypt and
decrypt passphrase-wrapped backups. The age private key rides *inside* the
backup; the backup itself is encrypted by the operator's passphrase — so the
passphrase is the single human-held secret and the key material travels with
the data it protects.

### answers-file

A YAML file of **operator inputs only** consumed by
`init-wizard.sh --non-interactive`. It carries identity, node address, SSH-key
references, and posture — but never generated secrets (passwords, tokens,
env_id, per-env keypairs stay wizard-internal and random). The answers-file is
the shared contract between the CLI wizard and the dmf-init web UI, and a copy
is bundled into each passphrase-wrapped backup so a restore can replay the
original inputs.

### appliance

The dmf-init container — a run-once, disposable container that puts a
localhost-only web UI on the dmf-env bootstrap toolchain, drives a blank node
to a verified cluster, and offers a passphrase-wrapped backup download at each
lifecycle checkpoint. You delete it when you're done; the downloaded backups
and your passphrase are all that remain. It commissions a cluster — it does not
build or emit a deployable image.

### checkpoint

A downloadable passphrase-wrapped backup taken at a lifecycle step during
bootstrap or management. Each checkpoint is a self-contained snapshot (env
state, age key, answers-file, manifest) encrypted with the operator's
passphrase and offered as a browser download.

### component repo

One of the eight purpose-specific repositories (dmf-cms, dmf-infra, dmf-env,
dmf-central, dmf-media, dmf-runbooks, dmf-init, dmf-promsd) that sit as
**siblings of the umbrella** under a common parent directory. Each is an
independent git repo with its own remote, release cycle, and agent-facing
conventions. Code edits go here; cross-cutting documentation goes in the
umbrella. See also [umbrella (repo)](#umbrella-repo).

### env

A deployment instance — everything needed to bootstrap and operate one cluster.
Per-env state (inventory, manifest, encrypted secrets bundle, SSH keypair,
OpenTofu state) lives entirely **operator-local** under
`~/.dmfdeploy/envs/<env>/`; nothing per-env is ever committed to a repo.
Tearing an env down is `rm -rf ~/.dmfdeploy/envs/<env>`.

### hetzner (provider)

The cloud provider profile: an ARM64 k3s cluster on Hetzner CAX21 instances,
provisioned via OpenTofu (`terraform/hetzner` + `terraform/modules/hetzner`).
Used when you need a real multi-node-like environment on cloud hardware rather
than a local VM.

### sandbox (provider)

The single-node provider profile for local experimentation — a Lima VM on
macOS, multipass/KVM on Linux, WSL2 on Windows, or any cheap VPS reachable
over SSH. Sandbox is the v0.1 release gate — the environment a newcomer is
expected to stand up first, before any cloud provider.

### umbrella (repo)

The dmfdeploy repository itself — the consolidated knowledge base (`docs/`)
and cross-repo coordination point for the DMF Platform. It holds architecture
documents, architecture decision records, plans, reviews, handoffs, and the
generated status snapshot. The eight component repos are its siblings, not its
children.
