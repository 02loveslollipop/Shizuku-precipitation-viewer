from __future__ import annotations

import logging
from datetime import datetime, timezone

import pandas as pd

from . import config
from .db import Database
from .pipeline import clean_measurements

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("cleaner")


def run() -> None:
    cfg = config.load()
    logger.info(
        "starting cleaner (lookback=%s, dry_run=%s, gbm_enabled=%s)",
        cfg.lookback,
        cfg.dry_run,
        cfg.gbm_enabled,
    )

    db = Database(cfg.database_url)
    cutoff = datetime.now(timezone.utc) - cfg.lookback
    raw_df = db.fetch_raw_measurements(cutoff)

    if raw_df.empty:
        logger.info("no raw measurements to process")
        return

    logger.info("fetched %d raw rows across %d sensors", len(raw_df), raw_df["sensor_id"].nunique())

    cleaned_df = clean_measurements(raw_df, cfg)
    if cleaned_df.empty:
        logger.info("nothing to insert after cleaning")
        return

    logger.info("prepared %d cleaned rows", len(cleaned_df))

    if cfg.dry_run:
        preview = cleaned_df.head().to_dict(orient="records")
        logger.info("dry-run enabled; skipping insert. preview=%s", preview)
        return

    inserted = db.insert_clean_measurements(cleaned_df.to_dict(orient="records"))
    logger.info("inserted %d rows into clean_measurements", inserted)


def main() -> None:
    try:
        run()
    except Exception:  # pragma: no cover - top-level logging
        logger.exception("cleaner failed")
        raise


if __name__ == "__main__":
    main()
