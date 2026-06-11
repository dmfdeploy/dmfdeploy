import pytest

from dmf_wizard.profiles import (
    PRESET_DEFAULTS,
    Profile,
    Tier,
    get_defaults,
)


def test_profile_values() -> None:
    assert Profile.CLOUD.value == "cloud"
    assert Profile.FLYPACK_OFFLINE.value == "flypack-offline"
    assert Profile.FLYPACK_ONLINE.value == "flypack-online"


def test_tier_values() -> None:
    assert Tier.RPI_MINIMAL.value == "rpi-minimal"
    assert Tier.LAB_3NODE.value == "lab-3node"
    assert Tier.SITE_HA.value == "site-ha"


def test_get_defaults_returns_copy() -> None:
    d1 = get_defaults(Profile.CLOUD, None)
    d1["dmf_node_count"] = 999
    d1["roles"]["cms"] = False
    d2 = get_defaults(Profile.CLOUD, None)
    assert d2["dmf_node_count"] != 999
    assert d2["roles"]["cms"] is True


def test_get_defaults_cloud_has_no_tier() -> None:
    d = get_defaults(Profile.CLOUD, None)
    assert d["dmf_node_count"] == 3
    assert d["dmf_storage_class"] == "longhorn"


def test_get_defaults_flypack_offline_requires_tier() -> None:
    with pytest.raises(ValueError, match="tier required"):
        get_defaults(Profile.FLYPACK_OFFLINE, None)


def test_get_defaults_flypack_offline_all_tiers_present() -> None:
    for tier in (Tier.RPI_MINIMAL, Tier.LAB_3NODE, Tier.SITE_HA):
        d = get_defaults(Profile.FLYPACK_OFFLINE, tier)
        assert "dmf_node_count" in d
        assert "roles" in d


def test_get_defaults_flypack_online_no_tier() -> None:
    d = get_defaults(Profile.FLYPACK_ONLINE, None)
    assert d["dmf_node_count"] == 1
    assert d["dmf_observability_profile"] == "agent"


def test_get_defaults_invalid_tier_for_profile() -> None:
    with pytest.raises(ValueError, match="not applicable"):
        get_defaults(Profile.CLOUD, Tier.RPI_MINIMAL)
    with pytest.raises(ValueError, match="not applicable"):
        get_defaults(Profile.FLYPACK_ONLINE, Tier.LAB_3NODE)


def test_all_presets_have_full_role_dict() -> None:
    all_keys: set[str] = set()
    for cfg in PRESET_DEFAULTS.values():
        all_keys.update(cfg["roles"].keys())
    assert all_keys, "expected at least one role"
    for key, cfg in PRESET_DEFAULTS.items():
        missing = all_keys - set(cfg["roles"].keys())
        assert not missing, f"preset {key} missing role keys: {missing}"


def test_flypack_online_has_ship_now_roles_per_adr_0022() -> None:
    d = get_defaults(Profile.FLYPACK_ONLINE, None)
    assert d["roles"]["zot"] is True
    assert d["roles"]["awx_execution_node"] is True
    assert d["roles"]["prometheus_agent"] is True
    assert d["roles"]["openbao"] is False
    assert d["roles"]["authentik"] is False
    assert d["roles"]["netbox"] is False
    assert d["roles"]["forgejo"] is False
    assert d["roles"]["cms"] is False
