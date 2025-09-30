from __future__ import annotations

from datetime import timedelta
from typing import List, Tuple

import pandas as pd
import sqlalchemy as sa

from .config import Config

GRID_RUN_INSERT_SQL = sa.text(
    """
    INSERT INTO grid_runs (ts, res_m, bbox, crs, status, created_at, updated_at)
    SELECT slot, :res_m, '[]'::jsonb, 'EPSG:3857', 'pending', NOW(), NOW()
    FROM (
        SELECT DISTINCT date_trunc(:interval_unit, ts) AS slot
        FROM clean_measurements
        WHERE ts >= NOW() - (:backfill_hours || ' hours')::interval
    ) AS slots
    LEFT JOIN grid_runs gr ON gr.ts = slots.slot AND gr.res_m = :res_m
    WHERE gr.id IS NULL
    ORDER BY slot
    LIMIT :limit
    """
)

PENDING_SLOTS_SQL = sa.text(
    """
    SELECT id, ts, res_m
    FROM grid_runs
    WHERE status = 'pending'
    ORDER BY ts DESC
    LIMIT :limit
    """
)

UPDATE_STATUS_SQL = sa.text(
    """
    UPDATE grid_runs
    SET status = :status,
        blob_url_npz = :npz_url,
        blob_url_json = :json_url,
        blob_url_contours = :contours_url,
        bbox = :bbox,
        message = :message,
        updated_at = NOW()
    WHERE id = :id
    """
)

FAIL_STATUS_SQL = sa.text(
    """
    UPDATE grid_runs
    SET status = 'failed', message = :message, updated_at = NOW()
    WHERE id = :id
    """
)

SNAPSHOT_QUERY = sa.text(
    """
    SELECT cm.sensor_id,
           cm.ts,
           cm.value_mm,
           cm.imputation_method,
           s.lat,
           s.lon
    FROM clean_measurements cm
    JOIN sensors s ON s.id = cm.sensor_id
    WHERE cm.ts >= :start AND cm.ts < :end
    ORDER BY cm.sensor_id
    """
)


class Database:
    def __init__(self, cfg: Config):
        self.engine = sa.create_engine(cfg.database_url, pool_pre_ping=True, future=True)
        self.cfg = cfg

    def ensure_slots(self) -> None:
        with self.engine.begin() as conn:
            conn.execute(
                GRID_RUN_INSERT_SQL,
                {
                    "res_m": self.cfg.grid_resolution_m,
                    "interval_unit": "hour" if self.cfg.grid_interval >= timedelta(hours=1) else "minute",
                    "backfill_hours": self.cfg.backfill_hours,
                    "limit": self.cfg.max_slots_per_run * 4,
                },
            )

    def fetch_pending_slots(self) -> List[Tuple[int, pd.Timestamp]]:
        with self.engine.begin() as conn:
            rows = conn.execute(
                PENDING_SLOTS_SQL,
                {"limit": self.cfg.max_slots_per_run},
            ).fetchall()
        result = []
        for row in rows:
            ts = pd.Timestamp(row.ts)
            if ts.tzinfo is None:
                ts = ts.tz_localize("UTC")
            else:
                ts = ts.tz_convert("UTC")
            result.append((row.id, ts))
        return result

    def load_snapshot(self, slot: pd.Timestamp) -> pd.DataFrame:
        start = slot
        end = slot + self.cfg.grid_interval
        with self.engine.begin() as conn:
            df = pd.read_sql(
                SNAPSHOT_QUERY,
                conn,
                params={"start": start, "end": end},
            )
        df["ts"] = pd.to_datetime(df["ts"], utc=True)
        return df

    def mark_success(
        self,
        run_id: int,
        bbox_json: str,
        npz_url: str,
        json_url: str,
        contours_url: str,
        message: str | None = None,
    ) -> None:
        with self.engine.begin() as conn:
            conn.execute(
                UPDATE_STATUS_SQL,
                {
                    "id": run_id,
                    "status": "done",
                    "bbox": bbox_json,
                    "npz_url": npz_url,
                    "json_url": json_url,
                    "contours_url": contours_url,
                    "message": message,
                },
            )

    def mark_failure(self, run_id: int, message: str) -> None:
        with self.engine.begin() as conn:
            conn.execute(FAIL_STATUS_SQL, {"id": run_id, "message": message[:1000]})
