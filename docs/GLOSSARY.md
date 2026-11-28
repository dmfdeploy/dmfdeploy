# Glossary

These are the project's own coined terms, the ones an outsider can't google.
Industry vocabulary (NMOS, SMPTE ST 2110, PTP, …) is intentionally out of
scope; if you don't know those, the [EBU DMF Reference Architecture](https://tech.ebu.ch/)
is the entry point.

### ADR

An architecture decision record. Each ADR in [docs/decisions/](decisions/INDEX.md)
states one decision, its status, and a one-line rule. Superseded ADRs link to
the ADR that replaced them. To change a decision, write a new ADR. A change of
direction starts as an RFC in GitHub Discussions.

### age key

An [age](https://age-encryption.org/) asymmetric keypair used to encrypt and
decrypt passphrase-wrapped backups. The age private key rides *inside* the
backup; the backup itself is encrypted by the operator's passphrase. The
passphrase is the single human-held secret and the key material travels with
the data it protects.

### answers-file

A YAML file of **operator inputs only** consumed by
`init-wizard.sh --non-interactive`. It carries identity, node address, SSH-key
references, and posture. It never carries generated secrets (passwords, tokens,
env_id, per-env keypairs stay wizard-internal and random). The answers-file is
the shared contract between the CLI wizard and the dmf-init web UI, and a copy
is bundled into each passphrase-wrapped backup so a restore can replay the
original inputs.

### appliance

The dmf-init container is a run-once, disposable container that puts a
localhost-only web UI on the dmf-env bootstrap toolchain, drives a blank node
to a verified cluster, and offers a passphrase-wrapped backup download at each
lifecycle checkpoint. You delete it when you're done; the downloaded backups
and your passphrase are all that remain. It commissions a cluster. It does not
build or emit a deployable image.

### Authentik

The identity provider that the platform installs. It signs users in, with passkeys, to the console, Forgejo and Zot.

### born inventory

The record of an environment that the installer writes into NetBox while it
installs the platform. The `dmf-born-inventory` role creates a Site and a
Cluster for the env, with the env's id, label, provider and architecture as
custom fields, and registers the platform's own services. The console and
monitoring read this record. Nothing has to add it by hand.

### catalog entry

The description of one deployable media function. A catalog entry is a YAML
manifest in the function's source repo, joined to a NetBox record that holds
its lifecycle state. The manifest holds the intent: layer, dependencies, and
the Configure and Finalise playbooks. The console shows the join and launches
the playbooks through AWX.

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

### Configure

The lifecycle stage that starts a media function and wires it up, after
Provision has made it available. Configure launches the workload, sets its
initial connections, and flips the NetBox lifecycle tag from `bootstrapped` to
`active`. It runs when an operator acts in the console, as an AWX job template
in `dmf-runbooks`. See [ADR-0012](decisions/0012-configure-stage-distinct-from-provision.md).

### Day-0

The first install of a platform on a blank node. The Day-0 installer is
[dmf-init](https://github.com/dmfdeploy/dmf-init), a container that drives the
node to a verified cluster. Work after that point, such as deploying a media
function, is not Day-0.

### env

A deployment instance: everything needed to bootstrap and operate one cluster.
Per-env state (inventory, manifest, encrypted secrets bundle, SSH keypair,
OpenTofu state) lives entirely **operator-local** under
`~/.dmfdeploy/envs/<env>/`. Nothing per-env is ever committed to a repo.
Tearing an env down is `rm -rf ~/.dmfdeploy/envs/<env>`.

### execution environment (EE)

The container image in which AWX runs a playbook. Catalog launchers run in
pods that AWX starts from one shared EE image, hosted in the cluster's own
registry (Zot). They never connect to a node over SSH. See
[ADR-0025](decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md).

### External Secrets Operator (ESO)

A Kubernetes operator that copies secrets from OpenBao into Kubernetes Secrets, so that pods can read them.

### Finalise

The lifecycle stage that removes a media function and returns it to the state
before Configure. The function's Finalise playbook, such as
`teardown-<key>.yml`, removes the workload and flips the NetBox tag back. In
the EBU lifecycle, the last stage is *Finalise & Review*. See
[ADR-0013](decisions/0013-media-function-catalog-model.md).

### flypack

A portable facility in a flight case: the small, travelling end of the range of
facilities the platform aims at, next to an outside broadcast truck. The
single-node sandbox is the proof surface for this profile. See
[ADR-0050](decisions/0050-flypack-mode-portable-offline-kit.md).

### Forgejo

The Git service that the platform installs in the cluster. AWX reads its playbook projects from it. Forgejo pull-mirrors the
`dmf-runbooks`, `dmf-media` and `dmf-infra` repos from GitHub, every hour by default.

### hetzner (provider)

The cloud provider profile: an ARM64 k3s cluster on Hetzner CAX21 instances,
provisioned via OpenTofu (`terraform/hetzner` + `terraform/modules/hetzner`).
Used when you need a real multi-node-like environment on cloud hardware rather
than a local VM.

### launcher

The playbook that AWX runs to deploy a media function. A launcher installs the
function's Helm chart from the cluster's registry, waits for its health check,
and updates the function's tag in NetBox. Launchers live in
[dmf-runbooks](https://github.com/dmfdeploy/dmf-runbooks), and each is
registered as an AWX job template named `media-*`.

### Longhorn

The storage system for Kubernetes volumes on the cloud provider profile. It replicates volumes across nodes and backs them up to
object storage.

### Media Function

A containerised media-processing or support/control function, such as a mixer,
format converter or NMOS registry. It is layer 5 of the EBU reference architecture. In this
project, a media function is described by a catalog entry and deployed as a
Helm chart.

### Media Workload

A group of media function instances that work together, such as a registry and
the nodes that register with it. In NetBox, the workload is the
`workload:<slug>` tag on each function instance. There is no separate NetBox
object for it. The EBU lifecycle stages apply to the workload as a whole. See
[ADR-0046](decisions/0046-first-class-media-workload-entity.md).

### Move 1

The first proof of the thesis: deploying an NMOS registry on ARM k3s through
the whole catalog chain, from console to AWX, Helm and NetBox. It closed on
2026-06-04. Move 2 was the vertical slice from the console
through AWX to NetBox ([JOURNEY](JOURNEY.md)). The [learnings](reviews/dmf-platform-move-1-learnings.md)
record the result.

### OpenBao

The secrets store of the platform. External Secrets Operator copies its secrets into Kubernetes.

### Path A

The design in which AWX reaches the k3s control node over SSH, with a public
key placed by cloud-init and the private key held in OpenBao. Path A now
applies only to AWX jobs that change the infrastructure. Catalog launchers
moved to in-cluster execution. See
[ADR-0016](decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md).

### sandbox (provider)

The single-node provider profile for local experimentation: a Lima VM on
macOS, multipass/KVM on Linux, WSL2 on Windows, or any cheap VPS reachable
over SSH. Sandbox is the v0.1 release gate. A newcomer is
expected to stand up this environment first, before any cloud provider.

### seed boundary

The point in a fresh bootstrap where secrets are first written into OpenBao
with the `seed-bao` command. Playbooks before it ("pre-seed") run with secrets
that the controller holds. Playbooks after it ("post-seed") read from OpenBao.
See the [bootstrap secrets design](plans/dmf-pre-bao-bootstrap-secrets-design.md).

### thesis-killer

An assumption that, if false, would make the project a different product. The
project named three. Move 1 answered the first, whether NMOS runs on commodity
k3s; the other two remain unproven. See [JOURNEY](JOURNEY.md).

### umbrella (repo)

The dmfdeploy repository itself. It is the consolidated knowledge base (`docs/`)
and cross-repo coordination point for the dmfdeploy platform. It holds architecture
documents, architecture decision records, plans, reviews, and the
generated status snapshot. The eight component repos are its siblings. They are not its
children.

### Zot

The container registry that the platform installs in the cluster. Pods pull images from it, and the launchers pull Helm charts from
it. A bootstrap playbook seeds it from GHCR, the public registry of the project.
