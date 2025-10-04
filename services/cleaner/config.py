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
    arima_enabled: bool
    arima_min_train: int
    arima_max_order: int
    arima_seasonal: bool
    arima_m: int


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

    arima_enabled = _parse_bool(os.getenv("CLEANER_ARIMA_ENABLED"), default=True)
    arima_min_train = _parse_int(os.getenv("CLEANER_ARIMA_MIN_TRAIN"), default=48)
    arima_max_order = _parse_int(os.getenv("CLEANER_ARIMA_MAX_ORDER"), default=3)
    arima_seasonal = _parse_bool(os.getenv("CLEANER_ARIMA_SEASONAL"), default=True)
    arima_m = _parse_int(os.getenv("CLEANER_ARIMA_M"), default=24)  # 24 hours for daily seasonality

    return Config(
        database_url=database_url,
        lookback=lookback,
        min_value_mm=min_value,
        max_value_mm=max_value,
        min_quality=min_quality,
        interpolation_limit=interpolation_limit,
        dry_run=dry_run,
        arima_enabled=arima_enabled,
        arima_min_train=arima_min_train,
        arima_max_order=arima_max_order,
        arima_seasonal=arima_seasonal,
        arima_m=arima_m,
    )
