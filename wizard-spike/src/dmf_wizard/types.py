from datetime import datetime
from enum import Enum

from pydantic import BaseModel

from dmf_wizard.profiles import Profile, Tier


class StepStatus(str, Enum):
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


class StepResult(BaseModel):
    name: str
    status: StepStatus
    started_at: datetime | None = None
    finished_at: datetime | None = None
    exit_code: int | None = None
    stdout_tail: str | None = None
    stderr_tail: str | None = None
    input_checksum: str | None = None
    error: str | None = None


class WizardState(BaseModel):
    schema_version: int = 1
    env_name: str
    profile: Profile
    tier: Tier | None = None
    created_at: datetime
    updated_at: datetime
    steps: dict[str, StepResult] = {}
