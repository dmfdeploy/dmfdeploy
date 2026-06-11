---
status: historical
date: 2026-05-08
---
# Multi-provider resource selection — future direction

**Date:** 2026-05-08
**Status:** Capture only — not a plan yet. Use as seed for a detailed plan in a later session.
**Source:** Operator note during aliyun readiness review.

## The eventual goal

From both the bootstrap scripts (operator-side) and from within `dmf-cms` (in-cluster console), the operator should be able to:

1. **Choose a provider per resource** — not per environment. A single environment manifest could declare:
   - compute: Aliyun ECS in eu-central-1
   - DNS: Cloudflare
   - object storage: Backblaze B2 or Aliyun OSS
   - load balancer: provider-native (Aliyun SLB) or self-hosted (MetalLB)
   - control plane: Hetzner Cloud while data plane runs on Aliyun (cross-cloud cluster)
2. **Choose the instance level** for compute resources — pick from the provider's catalogue (e.g. `ecs.g8y.large` vs `ecs.g8y.xlarge`).
3. **See live pricing** by querying provider APIs at selection time — not from a hard-coded price table that decays.
4. **Surface this in dmf-cms** so non-CLI users can build a Resource Profile interactively, with cost estimates per choice.

## Why this is interesting

- Today's `manifests/<env>.yaml` Resource Profile already declares intent at the right granularity. It's just not yet **interpreted** into provider-specific resources by anything other than hand-written Tofu.
- Aliyun Frankfurt rollout already exposed the seam: `dmf-env/tasks/aliyun_slb.yml` is a stub because the provider-specific work hasn't been factored. Same shape for object storage when we add it.
- The proposed Tofu module split (review §5 + chat 2026-05-08 — modules grouped by `<provider>/<role>`) is the **infrastructure** half of the same idea. Pricing + selection UI is the **planning** half.

## Sketch of the moving parts (for the future plan)

| Layer | Today | Future direction |
|---|---|---|
| Resource Profile manifest | Hand-written `manifests/<env>.yaml`. Declares intent + provider choices statically. | Generated/edited via dmf-cms with live provider data. Versioned in git as today (the SoT doesn't change — only the authoring path). |
| Provider catalogues | Implicit in Tofu module + `instance_type` strings. | Explicit catalogue per provider (`catalogue/aliyun.yaml`, `catalogue/hetzner.yaml`) — instance families, regions, SKUs, capabilities (ARM/x86, GPU, NIC count). Periodically synced from provider APIs. |
| Pricing | Not tracked. | Live query at selection time. Cache with TTL — providers don't always rate-limit kindly. |
| Provider auth for queries | Operator-side only (`~/.secure/aliyun/`, `~/.config/hcloud/`). | dmf-cms needs read-only catalogue+pricing creds. Separate AppRole or OIDC ServiceAccount, NOT the bootstrap creds. |
| Tofu modules | One module per `<provider>-cluster` (monolithic). | Split by `<provider>/<role>` (compute, dns, lb, oss). Composable — env workspace picks one of each. |
| dmf-cms UI | No provider awareness. | New "Plan environment" flow: pick role-by-role, see live pricing, save as Resource Profile, hand to Ansible/Tofu for apply. |
| Tofu apply path | `bin/tf-apply.sh <env>`. | Plus per-role: `bin/tf-apply.sh <env> compute`, `bin/tf-apply.sh <env> dns`, etc. Or one composer apply that walks all roles. |

## Provider API surface (rough notes for later research)

| Provider | Catalogue API | Pricing API | Auth |
|---|---|---|---|
| Aliyun | `DescribeInstanceTypes`, `DescribeRegions` | `DescribeProductsByPriceModule`, `DescribePrice` | RAM AccessKey, can be scoped read-only |
| Hetzner Cloud | `GET /v1/server_types`, `GET /v1/locations` | Static-ish; published via `prices` field on server_types and as `GET /v1/pricing` | API token (can be read-only) |
| Cloudflare | `GET /zones`, DNS API | Plans table, mostly static | API token, scoped read-only |
| Backblaze B2 | `b2_list_buckets`, region info | Public pricing page; programmatic via APIs not first-class | App key |
| AWS / GCP / Azure | (if we ever get there) | Mature pricing APIs but heavy IAM lift | TBD |

## Why this is NOT in scope today

- Aliyun rollout (Phase A of the readiness review) is the immediate blocker.
- Single operator + experiment phase (ADR-0004) — manual instance-type editing in `manifests/<env>.yaml` is fine for now.
- dmf-cms console is mid-refactor (passkey-only auth, Move 1 + Catalog work). Adding provider-pricing flows on top is premature.
- The Tofu module split (review §5, chat 2026-05-08) is the prerequisite. Until modules are factored by `<provider>/<role>`, there's nothing for a UI to compose.

## When this becomes real

The natural trigger is the **second non-trivial environment after aliyun**. By environment #3 the manual copy-paste-and-tweak pattern starts paying real cost; environment #2 is still small enough to do by hand and learn from.

A second trigger: dmf-cms gets a "Provision new environment" flow. Even a stub of that flow forces the catalogue + pricing question.

## Concrete next steps when we open the proper plan

1. Survey provider APIs for catalogue + pricing — assess auth surface, rate limits, response schema. Publish as `docs/research/provider-apis-2026-XX.md`.
2. Decide on the catalogue source-of-truth: provider-API-on-demand vs. cached YAML synced periodically. Tradeoff: freshness vs. dev-loop offline-ness.
3. Module-split spike: pick aliyun as the testbed, refactor `modules/aliyun-cluster/` into `modules/aliyun/compute/` + `modules/cloudflare/dns/`, observe what breaks. (This is the Phase A #5 alternative path from the review.)
4. dmf-cms UX sketch: provider picker, role picker, live pricing panel, "save as Resource Profile" output. Driven by `dmf-cms` design-shotgun pass.
5. ADR for the resource-profile-to-tofu interpretation layer (whatever shape it ends up — codegen, registry, Helm-style values, or runtime composer).

## Cross-references

- Review: `docs/reviews/dmf-aliyun-readiness-review-2026-05-08.md` (Phase A #5 — module split is the infra prerequisite)
- Manifest pattern: `dmf-env/manifests/aliyun.yaml` + `dmf-env/manifests/README.md` (Resource Profile schema sketch)
- Strategic frame: `docs/reviews/dmf-platform-strategic-review-2026-04-30.md` (experiment phase, thesis-killers)
- ADR-0004: experiment-phase stance (why this is deferred)

---

_End of capture. Open a proper `docs/plans/` doc when picking this up._
