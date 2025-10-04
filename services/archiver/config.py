"""
Configuration for the archiver service
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv


@dataclass(slots=True)
class ArchiverConfig:
    """Configuration for the data archiver service"""
    
    database_url: str
    blob_token: str
    blob_base_url: str
    
    # Retention policies (in days)
    raw_retention_days: int = 1  # Keep raw measurements for 1 day
    clean_retention_days: int = 30  # Archive clean measurements after 30 days
    
    # Processing options
    batch_size: int = 1000  # Number of records to process at once
    dry_run: bool = False  # If True, don't delete or upload
    

def _parse_int(value: Optional[str], default: int) -> int:
    """Parse integer from environment variable"""
    if value is None or value.strip() == "":
        return default
    try:
        return int(value)
    except ValueError:
        return default


def _parse_bool(value: Optional[str], default: bool = False) -> bool:
    """Parse boolean from environment variable"""
    if value is None or value.strip() == "":
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def load() -> ArchiverConfig:
    """Load configuration from environment variables"""
    load_dotenv(Path(".env"), override=False)

    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is required for archiver service")

    blob_token = os.getenv("VERCEL_BLOB_RW_TOKEN")
    if not blob_token:
        raise RuntimeError("VERCEL_BLOB_RW_TOKEN is required for archiver service")

    blob_base_url = os.getenv("VERCEL_BLOB_BASE_URL")
    if not blob_base_url:
        raise RuntimeError("VERCEL_BLOB_BASE_URL must be set")

    return ArchiverConfig(
        database_url=database_url,
        blob_token=blob_token,
        blob_base_url=blob_base_url,
        raw_retention_days=_parse_int(os.getenv("ARCHIVER_RAW_RETENTION_DAYS"), 1),
        clean_retention_days=_parse_int(os.getenv("ARCHIVER_CLEAN_RETENTION_DAYS"), 30),
        batch_size=_parse_int(os.getenv("ARCHIVER_BATCH_SIZE"), 1000),
        dry_run=_parse_bool(os.getenv("ARCHIVER_DRY_RUN"), False),
    )
