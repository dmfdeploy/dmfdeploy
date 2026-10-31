# docs/references/: external reference material

Third-party documents that DMF design work draws on, kept here so a parked
topic can be picked up without hunting for the source again. Each entry pairs
the original (only when its licence allows redistribution) with a DMF note
that summarises it and records why it matters.

These are **Record** docs: point-in-time inputs that record no DMF decision. Decisions
live in [ADRs](../decisions/INDEX.md); scheduling lives in
[GitHub Issues](https://github.com/dmfdeploy/dmfdeploy/issues).

| Reference | Licence | DMF note | Relevant to |
|---|---|---|---|
| IAMT *Dynamic Software Licensing: Best Practices* v1.0.0 (2026-09-07), [PDF](iamt-dynamic-software-licensing-best-practices-v1.0.0.pdf) | Apache-2.0 (licence text is in the PDF's final section) | [Summary and DMF relevance](iamt-dsl-v1-0-0-summary-and-relevance.md) | [ADR-0045](../decisions/0045-media-function-licensing-reservable-resource.md) licensing RFC (parked; #245 track) |
| Survey of open specifications for media function configuration control (2026-10-22) | Project survey of public sources | [Configuration control survey](media-function-configuration-control-survey.md) | [#685](https://github.com/dmfdeploy/dmfdeploy/issues/685) RFC, [#634](https://github.com/dmfdeploy/dmfdeploy/issues/634); [ADR-0012](../decisions/0012-configure-stage-distinct-from-provision.md), [ADR-0013](../decisions/0013-media-function-catalog-model.md), [ADR-0046](../decisions/0046-first-class-media-workload-entity.md), [ADR-0047](../decisions/0047-media-function-packaging-catalog-sources-trust-model.md) |
| Survey of open specifications for media function telemetry declaration (2026-10-22) | Project survey of public sources | [Telemetry declaration survey](media-function-telemetry-declaration-survey.md) | [#685](https://github.com/dmfdeploy/dmfdeploy/issues/685) RFC, [#634](https://github.com/dmfdeploy/dmfdeploy/issues/634); [ADR-0038](../decisions/0038-netbox-driven-dynamic-monitoring.md), [ADR-0045](../decisions/0045-media-function-licensing-reservable-resource.md), [ADR-0047](../decisions/0047-media-function-packaging-catalog-sources-trust-model.md) |
| Survey of media orchestration and parameter control: orchestrators, translators and standards (2026-10-22) | Project survey of public sources | [Orchestration and parameter control survey](media-function-orchestration-control-survey.md) | [#685](https://github.com/dmfdeploy/dmfdeploy/issues/685) RFC, [#634](https://github.com/dmfdeploy/dmfdeploy/issues/634); [ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md), [ADR-0037](../decisions/0037-media-workloads-netbox-instance-inventory.md), [ADR-0043](../decisions/0043-workload-scale-to-zero-availability.md), [ADR-0047](../decisions/0047-media-function-packaging-catalog-sources-trust-model.md) |
| EBU Dynamic Media Facility overview talk (published 2025-10-01) | Project summary of a public talk; the video is the original | [Comparison register](ebu-dmf-video-ip-showcase-overview.md) | [ADR-0003](../decisions/0003-ebu-v2-taxonomy.md), [ADR-0013](../decisions/0013-media-function-catalog-model.md), [ADR-0017](../decisions/0017-mxl-intra-host-data-plane.md), [ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md), [ADR-0046](../decisions/0046-first-class-media-workload-entity.md) |
