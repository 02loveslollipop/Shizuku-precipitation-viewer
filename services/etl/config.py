from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import timedelta
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv


def _get_database_url() -> str:
    """Get database URL with support for Heroku's dynamic env variable names.
    
    Reads DB_ENV_VARIABLE to get the actual env variable name containing the database URL.
    This handles Heroku's random DATABASE_URL naming (e.g., HEROKU_POSTGRESQL_PURPLE_URL).
    Also fixes postgres:// to postgresql:// for Python compatibility.
    """
    # First check if we have an indirection variable
    db_env_var_name = os.getenv("DB_ENV_VARIABLE", "DATABASE_URL")
    database_url = os.getenv(db_env_var_name)
    
    if not database_url:
        raise RuntimeError(f"{db_env_var_name} is required for ETL service (specified by DB_ENV_VARIABLE={db_env_var_name})")
    
    # Fix postgres:// to postgresql:// for Python compatibility
    if database_url.startswith("postgres://"):
        database_url = database_url.replace("postgres://", "postgresql://", 1)
    
    return database_url


@dataclass(slots=True)
class Config:
    database_url: str
    blob_token: str
    blob_base_url: str
    grid_interval: timedelta
    grid_resolution_m: int
    grid_padding_m: int
    max_slots_per_run: int
    backfill_hours: int
    dry_run: bool


def _parse_int(value: Optional[str], default: int) -> int:
    if value is None or value.strip() == "":
        return default
    return int(value)


def _parse_bool(value: Optional[str], default: bool = False) -> bool:
    if value is None or value.strip() == "":
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def load() -> Config:
    load_dotenv(Path(".env"), override=False)

    database_url = _get_database_url()

    blob_token = os.getenv("VERCEL_BLOB_RW_TOKEN")
    if not blob_token:
        raise RuntimeError("VERCEL_BLOB_RW_TOKEN is required for ETL service")

    blob_base_url = os.getenv("VERCEL_BLOB_BASE_URL")
    if not blob_base_url:
        raise RuntimeError("VERCEL_BLOB_BASE_URL must be set (e.g. https://...vercel-storage.com)")

    interval_min = _parse_int(os.getenv("GRID_INTERVAL_MIN"), default=60)
    grid_resolution = _parse_int(os.getenv("GRID_RESOLUTION_M"), default=500)
    padding = _parse_int(os.getenv("GRID_PADDING_M"), default=2000)
    max_slots = _parse_int(os.getenv("ETL_MAX_SLOTS"), default=3)
    backfill_hours = _parse_int(os.getenv("ETL_BACKFILL_HOURS"), default=48)
    dry_run = _parse_bool(os.getenv("DRY_RUN"), default=False)

    return Config(
        database_url=database_url,
        blob_token=blob_token,
        blob_base_url=blob_base_url.rstrip('/'),
        grid_interval=timedelta(minutes=interval_min),
        grid_resolution_m=grid_resolution,
        grid_padding_m=padding,
        max_slots_per_run=max_slots,
        backfill_hours=backfill_hours,
        dry_run=dry_run,
    )
