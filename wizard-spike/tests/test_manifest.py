from pathlib import Path

import pytest
from pydantic import ValidationError

from dmf_wizard.manifest import (
    CloudManifest,
    FlypackOfflineManifest,
    FlypackOnlineManifest,
    HubReference,
    Manifest,
    build_manifest,
    dump_yaml,
    load_yaml,
)
from dmf_wizard.profiles import Profile, Tier


def _hub() -> HubReference:
    return HubReference(
        url="https://hub.example.com",
        trust_anchor_sha256="a" * 64,
        edge_id="edge-001",
    )


def test_build_cloud_manifest() -> None:
    m = build_manifest(Profile.CLOUD, None, env_name="prod")
    assert isinstance(m.body, CloudManifest)
    assert m.body.profile == Profile.CLOUD
    assert m.body.tier is None
    assert m.body.dmf_node_count == 3
    assert m.body.dmf_storage_class == "longhorn"
    assert m.body.roles["cms"] is True


def test_build_flypack_offline_rpi_minimal() -> None:
    m = build_manifest(Profile.FLYPACK_OFFLINE, Tier.RPI_MINIMAL, env_name="rpi1")
    assert isinstance(m.body, FlypackOfflineManifest)
    assert m.body.tier == Tier.RPI_MINIMAL
    assert m.body.dmf_node_count == 1
    assert m.body.dmf_storage_class == "local-path"


def test_build_flypack_offline_lab_3node() -> None:
    m = build_manifest(Profile.FLYPACK_OFFLINE, Tier.LAB_3NODE, env_name="lab")
    assert isinstance(m.body, FlypackOfflineManifest)
    assert m.body.tier == Tier.LAB_3NODE
    assert m.body.dmf_node_count == 3
    assert m.body.dmf_ingress_mode == "metallb-l2"


def test_build_flypack_offline_site_ha() -> None:
    m = build_manifest(Profile.FLYPACK_OFFLINE, Tier.SITE_HA, env_name="site")
    assert isinstance(m.body, FlypackOfflineManifest)
    assert m.body.tier == Tier.SITE_HA
    assert m.body.dmf_node_count == 5


def test_build_flypack_online_with_hub() -> None:
    m = build_manifest(
        Profile.FLYPACK_ONLINE, None, env_name="edge-001", hub=_hub()
    )
    assert isinstance(m.body, FlypackOnlineManifest)
    assert m.body.hub.edge_id == "edge-001"
    assert m.body.roles["zot"] is True
    assert m.body.roles["awx_execution_node"] is True
    assert m.body.roles["openbao"] is False


def test_build_flypack_online_without_hub_raises() -> None:
    with pytest.raises(ValueError, match="hub reference required"):
        build_manifest(Profile.FLYPACK_ONLINE, None, env_name="edge-001")


def test_build_cloud_with_hub_raises() -> None:
    with pytest.raises(ValueError, match="hub only applies"):
        build_manifest(Profile.CLOUD, None, env_name="prod", hub=_hub())


def test_build_applies_flat_override() -> None:
    m = build_manifest(
        Profile.CLOUD,
        None,
        env_name="prod",
        overrides={"dmf_node_count": 7},
    )
    assert m.body.dmf_node_count == 7


def test_build_applies_role_override() -> None:
    m = build_manifest(
        Profile.CLOUD,
        None,
        env_name="prod",
        overrides={"roles": {"netbox": False}},
    )
    assert m.body.roles["netbox"] is False
    # Other roles untouched.
    assert m.body.roles["cms"] is True
    assert m.body.roles["openbao"] is True


def _roundtrip(m: Manifest, tmp_path: Path) -> Manifest:
    path = tmp_path / "manifest.yaml"
    dump_yaml(m, path)
    return load_yaml(path)


def test_yaml_roundtrip_cloud(tmp_path: Path) -> None:
    m = build_manifest(Profile.CLOUD, None, env_name="prod")
    loaded = _roundtrip(m, tmp_path)
    assert isinstance(loaded.body, CloudManifest)
    assert loaded.body.env_name == "prod"
    assert loaded.body.dmf_node_count == m.body.dmf_node_count
    assert loaded.body.roles == m.body.roles


def test_yaml_roundtrip_flypack_offline(tmp_path: Path) -> None:
    m = build_manifest(
        Profile.FLYPACK_OFFLINE, Tier.LAB_3NODE, env_name="lab"
    )
    loaded = _roundtrip(m, tmp_path)
    assert isinstance(loaded.body, FlypackOfflineManifest)
    assert loaded.body.tier == Tier.LAB_3NODE


def test_yaml_roundtrip_flypack_online(tmp_path: Path) -> None:
    m = build_manifest(
        Profile.FLYPACK_ONLINE, None, env_name="edge-001", hub=_hub()
    )
    loaded = _roundtrip(m, tmp_path)
    assert isinstance(loaded.body, FlypackOnlineManifest)
    assert loaded.body.hub.edge_id == "edge-001"


def test_yaml_emitted_keys_in_declared_order(tmp_path: Path) -> None:
    m = build_manifest(Profile.CLOUD, None, env_name="prod")
    path = tmp_path / "m.yaml"
    dump_yaml(m, path)
    text = path.read_text(encoding="utf-8")
    # Top-level keys appear in declared order.
    idx_schema = text.index("schema_version")
    idx_gen_at = text.index("generated_at")
    idx_gen = text.index("generator:")
    idx_body = text.index("body:")
    assert idx_schema < idx_gen_at < idx_gen < idx_body


def test_yaml_load_rejects_unknown_profile(tmp_path: Path) -> None:
    path = tmp_path / "bad.yaml"
    path.write_text(
        "schema_version: 1\n"
        "generated_at: '2026-05-13T00:00:00+00:00'\n"
        "generator: 'dmf-wizard-spike/0.0.1'\n"
        "body:\n"
        "  profile: bogus\n"
        "  env_name: x\n",
        encoding="utf-8",
    )
    with pytest.raises(ValidationError):
        load_yaml(path)


def test_yaml_load_rejects_schema_version_mismatch(tmp_path: Path) -> None:
    m = build_manifest(Profile.CLOUD, None, env_name="prod")
    path = tmp_path / "m.yaml"
    dump_yaml(m, path)
    text = path.read_text(encoding="utf-8")
    text = text.replace("schema_version: 1", "schema_version: 99")
    path.write_text(text, encoding="utf-8")
    with pytest.raises(ValidationError):
        load_yaml(path)


def test_manifest_envelope_fields(tmp_path: Path) -> None:
    m = build_manifest(Profile.CLOUD, None, env_name="prod")
    assert m.schema_version == 1
    assert m.generator == "dmf-wizard-spike/0.0.1"
    assert m.generated_at is not None
