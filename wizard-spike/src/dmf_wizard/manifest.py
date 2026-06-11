"""Discriminated-union Manifest pydantic model with ruamel.yaml emitter."""

import io
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated, Any, Literal, Union

from pydantic import BaseModel, Field
from ruamel.yaml import YAML

from dmf_wizard.profiles import Profile, Tier, get_defaults
from dmf_wizard.state import atomic_write_text


GENERATOR_NAME = "dmf-wizard-spike"
GENERATOR_VERSION = "0.0.1"
MANIFEST_SCHEMA_VERSION = 1


def _generator_string() -> str:
    return f"{GENERATOR_NAME}/{GENERATOR_VERSION}"


class HubReference(BaseModel):
    """Pairing material for flypack-online edges (per ADR-0022)."""

    url: str
    trust_anchor_sha256: str
    edge_id: str


class CloudManifest(BaseModel):
    profile: Literal[Profile.CLOUD] = Profile.CLOUD
    tier: None = None
    env_name: str
    dmf_node_count: int
    dmf_storage_class: str
    dmf_storage_topology: str
    dmf_ingress_mode: str
    dmf_cloud_lb_enabled: bool
    dmf_longhorn_enabled: bool
    dmf_observability_profile: str
    roles: dict[str, bool]


class FlypackOfflineManifest(BaseModel):
    profile: Literal[Profile.FLYPACK_OFFLINE] = Profile.FLYPACK_OFFLINE
    tier: Tier
    env_name: str
    dmf_node_count: int
    dmf_storage_class: str
    dmf_storage_topology: str
    dmf_ingress_mode: str
    dmf_cloud_lb_enabled: bool
    dmf_longhorn_enabled: bool
    dmf_observability_profile: str
    roles: dict[str, bool]


class FlypackOnlineManifest(BaseModel):
    profile: Literal[Profile.FLYPACK_ONLINE] = Profile.FLYPACK_ONLINE
    tier: None = None
    env_name: str
    hub: HubReference
    dmf_node_count: int
    dmf_storage_class: str
    dmf_storage_topology: str
    dmf_ingress_mode: str
    dmf_cloud_lb_enabled: bool
    dmf_longhorn_enabled: bool
    dmf_observability_profile: str
    roles: dict[str, bool]


ManifestBody = Annotated[
    Union[CloudManifest, FlypackOfflineManifest, FlypackOnlineManifest],
    Field(discriminator="profile"),
]


class Manifest(BaseModel):
    """Top-level manifest envelope with schema version + generator metadata."""

    schema_version: Literal[1] = MANIFEST_SCHEMA_VERSION
    generated_at: datetime
    generator: str
    body: ManifestBody


def _yaml() -> YAML:
    y = YAML(typ="safe", pure=True)
    y.default_flow_style = False
    y.sort_base_mapping_type_on_output = False
    y.indent(mapping=2, sequence=4, offset=2)
    return y


def build_manifest(
    profile: Profile,
    tier: Tier | None,
    env_name: str,
    overrides: dict[str, Any] | None = None,
    hub: HubReference | None = None,
) -> Manifest:
    """Build a Manifest by merging preset defaults with operator overrides."""
    if profile == Profile.FLYPACK_ONLINE and hub is None:
        raise ValueError("hub reference required for flypack-online")
    if profile != Profile.FLYPACK_ONLINE and hub is not None:
        raise ValueError("hub only applies to flypack-online")

    defaults = get_defaults(profile, tier)

    if overrides:
        for key, value in overrides.items():
            if key == "roles" and isinstance(value, dict):
                defaults["roles"].update(value)
            else:
                defaults[key] = value

    common: dict[str, Any] = {"env_name": env_name, **defaults}

    body: ManifestBody
    if profile == Profile.CLOUD:
        body = CloudManifest(**common)
    elif profile == Profile.FLYPACK_OFFLINE:
        assert tier is not None
        body = FlypackOfflineManifest(tier=tier, **common)
    else:
        assert hub is not None
        body = FlypackOnlineManifest(hub=hub, **common)

    return Manifest(
        schema_version=MANIFEST_SCHEMA_VERSION,
        generated_at=datetime.now(timezone.utc),
        generator=_generator_string(),
        body=body,
    )


def _ordered_payload(manifest: Manifest) -> dict[str, Any]:
    """Convert a Manifest to a plain dict with deterministic key order."""
    raw = manifest.model_dump(mode="json")
    body = raw["body"]
    # Field declaration order is preserved by pydantic v2 model_dump,
    # but rebuild the top-level dict explicitly to be deterministic.
    return {
        "schema_version": raw["schema_version"],
        "generated_at": raw["generated_at"],
        "generator": raw["generator"],
        "body": body,
    }


def dump_yaml(manifest: Manifest, path: Path) -> None:
    """Write the manifest to disk as YAML. Deterministic ordering, atomic write."""
    payload = _ordered_payload(manifest)
    buf = io.StringIO()
    _yaml().dump(payload, buf)
    atomic_write_text(path, buf.getvalue())


def load_yaml(path: Path) -> Manifest:
    """Load and validate a manifest YAML file."""
    with open(path, "r", encoding="utf-8") as f:
        data = _yaml().load(f)
    return Manifest.model_validate(data)
