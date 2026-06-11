"""Canonical Profile/Tier enums and preset defaults table for the DMF wizard."""

import copy
from enum import Enum
from typing import Any


class Profile(str, Enum):
    CLOUD = "cloud"
    FLYPACK_OFFLINE = "flypack-offline"
    FLYPACK_ONLINE = "flypack-online"


class Tier(str, Enum):
    """Sizing tier; only meaningful when profile == FLYPACK_OFFLINE."""

    RPI_MINIMAL = "rpi-minimal"
    LAB_3NODE = "lab-3node"
    SITE_HA = "site-ha"


# Canonical defaults table per Step 1 of the survey doc round-2 decisions.
# Keyed by (profile, tier). tier is None for cloud and flypack-online.
# Eventual home: dmf-infra defaults (Step 1 follow-up); kept here for spike.
PRESET_DEFAULTS: dict[tuple[Profile, Tier | None], dict[str, Any]] = {
    (Profile.CLOUD, None): {
        "dmf_node_count": 3,
        "dmf_storage_class": "longhorn",
        "dmf_storage_topology": "distributed-rwx",
        "dmf_ingress_mode": "cloud-native",
        "dmf_cloud_lb_enabled": True,
        "dmf_longhorn_enabled": True,
        "dmf_observability_profile": "full",
        "roles": {
            "openbao": True,
            "authentik": True,
            "zot": True,
            "netbox": True,
            "awx": True,
            "awx_execution_node": False,
            "forgejo": True,
            "grafana": True,
            "prometheus": True,
            "prometheus_agent": False,
            "loki": True,
            "cms": True,
        },
    },
    (Profile.FLYPACK_OFFLINE, Tier.RPI_MINIMAL): {
        "dmf_node_count": 1,
        "dmf_storage_class": "local-path",
        "dmf_storage_topology": "single-node-rwo",
        "dmf_ingress_mode": "nodeport-only",
        "dmf_cloud_lb_enabled": False,
        "dmf_longhorn_enabled": False,
        "dmf_observability_profile": "slim",
        "roles": {
            "openbao": True,
            "authentik": True,
            "zot": True,
            "netbox": True,
            "awx": True,
            "awx_execution_node": False,
            "forgejo": True,
            "grafana": True,
            "prometheus": True,
            "prometheus_agent": False,
            "loki": True,
            "cms": True,
        },
    },
    (Profile.FLYPACK_OFFLINE, Tier.LAB_3NODE): {
        "dmf_node_count": 3,
        "dmf_storage_class": "longhorn",
        "dmf_storage_topology": "distributed-rwx",
        "dmf_ingress_mode": "metallb-l2",
        "dmf_cloud_lb_enabled": False,
        "dmf_longhorn_enabled": True,
        "dmf_observability_profile": "normal",
        "roles": {
            "openbao": True,
            "authentik": True,
            "zot": True,
            "netbox": True,
            "awx": True,
            "awx_execution_node": False,
            "forgejo": True,
            "grafana": True,
            "prometheus": True,
            "prometheus_agent": False,
            "loki": True,
            "cms": True,
        },
    },
    (Profile.FLYPACK_OFFLINE, Tier.SITE_HA): {
        "dmf_node_count": 5,
        "dmf_storage_class": "longhorn",
        "dmf_storage_topology": "distributed-rwx",
        "dmf_ingress_mode": "metallb-l2",
        "dmf_cloud_lb_enabled": False,
        "dmf_longhorn_enabled": True,
        "dmf_observability_profile": "full",
        "roles": {
            "openbao": True,
            "authentik": True,
            "zot": True,
            "netbox": True,
            "awx": True,
            "awx_execution_node": False,
            "forgejo": True,
            "grafana": True,
            "prometheus": True,
            "prometheus_agent": False,
            "loki": True,
            "cms": True,
        },
    },
    (Profile.FLYPACK_ONLINE, None): {
        # Per ADR-0022: thin edge, hub-paired. Only ship-now roles enabled.
        "dmf_node_count": 1,
        "dmf_storage_class": "local-path",
        "dmf_storage_topology": "single-node-rwo",
        "dmf_ingress_mode": "nodeport-only",
        "dmf_cloud_lb_enabled": False,
        "dmf_longhorn_enabled": False,
        "dmf_observability_profile": "agent",
        "roles": {
            "openbao": False,
            "authentik": False,
            "zot": True,
            "netbox": False,
            "awx": False,
            "awx_execution_node": True,
            "forgejo": False,
            "grafana": False,
            "prometheus": False,
            "prometheus_agent": True,
            "loki": False,
            "cms": False,
        },
    },
}


VALID_TIERS_FOR_PROFILE: dict[Profile, set[Tier | None]] = {
    Profile.CLOUD: {None},
    Profile.FLYPACK_OFFLINE: {Tier.RPI_MINIMAL, Tier.LAB_3NODE, Tier.SITE_HA},
    Profile.FLYPACK_ONLINE: {None},
}


def get_defaults(profile: Profile, tier: Tier | None) -> dict[str, Any]:
    """Return a deep copy of the defaults for (profile, tier)."""
    valid = VALID_TIERS_FOR_PROFILE[profile]
    if tier not in valid:
        if tier is None:
            raise ValueError(f"tier required for profile {profile.value}")
        if None in valid:
            raise ValueError(f"tier not applicable for profile {profile.value}")
        raise ValueError(
            f"tier {tier.value} not valid for profile {profile.value}"
        )
    return copy.deepcopy(PRESET_DEFAULTS[(profile, tier)])
