from __future__ import annotations

import logging
import os
from datetime import timedelta

import pandas as pd

from .config import load
from .db import Database
from .pipeline import clean_measurements

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("cleaner-backfill")


def run() -> None:
    cfg = load()
    chunk_hours = int(os.getenv("BACKFILL_CHUNK_HOURS", "24"))
    logger.info(
        "starting cleaning backfill (chunk=%sh, dry_run=%s)",
        chunk_hours,
        cfg.dry_run,
    )

    db = Database(cfg.database_url)
    min_ts, max_ts = db.raw_time_bounds()
    if not min_ts or not max_ts:
        logger.info("no raw measurements found")
        return

    logger.info("raw bounds: %s to %s", min_ts, max_ts)

    current = min_ts.floor("1h")
    chunk_delta = timedelta(hours=chunk_hours)

    processed = 0
    inserted = 0

    while current < max_ts:
        window_end = min(current + chunk_delta, max_ts + timedelta(hours=1))
        logger.info("processing window %s → %s", current, window_end)
        raw_df = db.fetch_raw_range(current, window_end)
        if raw_df.empty:
            logger.info("window empty; skipping")
            current = window_end
            continue

        cleaned_df = clean_measurements(raw_df, cfg)
        processed += len(raw_df)

        if cleaned_df.empty:
            logger.info("no cleaned rows produced for window")
        elif cfg.dry_run:
            logger.info("dry-run: %s cleaned rows (first=%s)", len(cleaned_df), cleaned_df.head(1))
        else:
            inserted_rows = db.insert_clean_measurements(cleaned_df.to_dict(orient="records"))
            inserted += inserted_rows
            logger.info("inserted %s rows", inserted_rows)

        current = window_end

    logger.info("finished backfill processed=%s inserted=%s", processed, inserted)


def main() -> None:
    try:
        run()
    except Exception:  # pragma: no cover
        logger.exception("cleaner backfill failed")
        raise


if __name__ == "__main__":
    main()
