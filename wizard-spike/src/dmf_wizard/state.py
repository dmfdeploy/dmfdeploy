import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

from pydantic import ValidationError

from dmf_wizard.types import WizardState


CURRENT_SCHEMA_VERSION = 1


class StateCorrupt(Exception):
    """Raised when the state file cannot be parsed or has an unknown schema."""


def atomic_write_text(path: Path, content: str) -> None:
    """Atomic write with parent-dir fsync for Linux durability."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    with open(tmp_path, "w", encoding="utf-8") as f:
        f.write(content)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp_path, path)
    try:
        dir_fd = os.open(str(path.parent), os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except (OSError, AttributeError):
        # Platforms without directory fsync (Windows) silently skip.
        pass


def load_state(path: Path) -> WizardState | None:
    """Load state from disk, returning None if missing."""
    if not path.exists():
        return None
    try:
        raw = path.read_text(encoding="utf-8")
        data = json.loads(raw)
    except (json.JSONDecodeError, OSError) as e:
        raise StateCorrupt(f"failed to parse state at {path}: {e}") from e
    schema_version = data.get("schema_version")
    if schema_version != CURRENT_SCHEMA_VERSION:
        raise StateCorrupt(
            f"unsupported schema_version {schema_version!r} at {path}"
        )
    try:
        return WizardState.model_validate(data)
    except ValidationError as e:
        raise StateCorrupt(f"invalid state at {path}: {e}") from e


def save_state(path: Path, state: WizardState) -> None:
    """Atomically persist state to disk."""
    state.updated_at = datetime.now(timezone.utc)
    payload = state.model_dump_json()
    atomic_write_text(path, payload)


def checksum_inputs(inputs: dict) -> str:
    """Deterministic sha256 hex digest of an input dict."""
    encoded = json.dumps(inputs, sort_keys=True, default=str).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()
