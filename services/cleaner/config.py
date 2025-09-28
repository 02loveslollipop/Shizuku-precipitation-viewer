from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import timedelta
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv


@dataclass(slots=True)
class Config:
    database_url: str
    lookback: timedelta
    min_value_mm: float
    max_value_mm: float
    min_quality: Optional[float]
    interpolation_limit: int
    dry_run: bool
    gbm_enabled: bool
    gbm_max_depth: int
    gbm_learning_rate: float
    gbm_min_train: int
    gbm_max_iters: int
    gbm_random_state: Optional[int]


def _parse_float(value: Optional[str], default: float) -> float:
    if value is None or value.strip() == "":
        return default
    return float(value)


def _parse_optional_float(value: Optional[str]) -> Optional[float]:
    if value is None or value.strip() == "":
        return None
    return float(value)


def _parse_int(value: Optional[str], default: int) -> int:
    if value is None or value.strip() == "":
        return default
    return int(value)


def _parse_bool(value: Optional[str], default: bool = False) -> bool:
    if value is None or value.strip() == "":
        return default
    value = value.strip().lower()
    return value in {"1", "true", "yes"}


def _parse_optional_int(value: Optional[str]) -> Optional[int]:
    if value is None or value.strip() == "":
        return None
    return int(value)


def load() -> Config:
    load_dotenv(dotenv_path=Path(".env"), override=False)

    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is required")

    lookback_hours = _parse_int(os.getenv("CLEANER_LOOKBACK_HOURS"), default=72)
    lookback = timedelta(hours=lookback_hours)

    min_value = _parse_float(os.getenv("CLEANER_MIN_VALUE_MM"), default=0.0)
    max_value = _parse_float(os.getenv("CLEANER_MAX_VALUE_MM"), default=150.0)
    min_quality = _parse_optional_float(os.getenv("CLEANER_MIN_QUALITY"))
    interpolation_limit = _parse_int(os.getenv("CLEANER_INTERPOLATION_LIMIT"), default=6)
    dry_run = _parse_bool(os.getenv("DRY_RUN"), default=False)

    gbm_enabled = _parse_bool(os.getenv("CLEANER_GBM_ENABLED"), default=True)
    gbm_max_depth = _parse_int(os.getenv("CLEANER_GBM_MAX_DEPTH"), default=3)
    gbm_learning_rate = _parse_float(os.getenv("CLEANER_GBM_LEARNING_RATE"), default=0.1)
    gbm_min_train = _parse_int(os.getenv("CLEANER_GBM_MIN_TRAIN"), default=48)
    gbm_max_iters = _parse_int(os.getenv("CLEANER_GBM_MAX_ITERS"), default=10)
    gbm_random_state = _parse_optional_int(os.getenv("CLEANER_GBM_RANDOM_STATE"))

    return Config(
        database_url=database_url,
        lookback=lookback,
        min_value_mm=min_value,
        max_value_mm=max_value,
        min_quality=min_quality,
        interpolation_limit=interpolation_limit,
        dry_run=dry_run,
        gbm_enabled=gbm_enabled,
        gbm_max_depth=gbm_max_depth,
        gbm_learning_rate=gbm_learning_rate,
        gbm_min_train=gbm_min_train,
        gbm_max_iters=gbm_max_iters,
        gbm_random_state=gbm_random_state,
    )
