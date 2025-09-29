from __future__ import annotations

from datetime import datetime
from typing import Iterable, Tuple

import pandas as pd
import sqlalchemy as sa
from sqlalchemy import text
from sqlalchemy.dialects.postgresql import insert

RAW_QUERY = """
SELECT rm.sensor_id,
       rm.ts,
       rm.value_mm,
       rm.quality,
       rm.variable,
       rm.source
FROM raw_measurements rm
LEFT JOIN clean_measurements cm
  ON cm.sensor_id = rm.sensor_id
 AND cm.ts = rm.ts
 AND cm.version = 1
WHERE rm.ts >= :since
  AND cm.id IS NULL
  AND rm.variable = 'precipitacion'
ORDER BY rm.sensor_id, rm.ts
"""

RAW_RANGE_QUERY = """
SELECT rm.sensor_id,
       rm.ts,
       rm.value_mm,
       rm.quality,
       rm.variable,
       rm.source
FROM raw_measurements rm
LEFT JOIN clean_measurements cm
  ON cm.sensor_id = rm.sensor_id
 AND cm.ts = rm.ts
 AND cm.version = 1
WHERE rm.ts >= :start
  AND rm.ts < :end
  AND cm.id IS NULL
  AND rm.variable = 'precipitacion'
ORDER BY rm.sensor_id, rm.ts
"""

BOUNDS_QUERY = """
SELECT MIN(ts) AS min_ts, MAX(ts) AS max_ts
FROM raw_measurements
WHERE variable = 'precipitacion'
"""


class Database:
    def __init__(self, url: str) -> None:
        self.engine = sa.create_engine(url, pool_pre_ping=True, future=True)
        self._metadata = sa.MetaData()
        self._clean_table = sa.Table(
            "clean_measurements",
            self._metadata,
            autoload_with=self.engine,
        )

    def fetch_raw_measurements(self, since: datetime) -> pd.DataFrame:
        stmt = text(RAW_QUERY)
        df = pd.read_sql(stmt, self.engine, params={"since": since})
        if not df.empty:
            df["ts"] = pd.to_datetime(df["ts"], utc=True)
        return df

    def insert_clean_measurements(self, rows: Iterable[dict]) -> int:
        rows = list(rows)
        if not rows:
            return 0

        stmt = insert(self._clean_table).values(rows)
        update_cols = {
            "value_mm": stmt.excluded.value_mm,
            "qc_flags": stmt.excluded.qc_flags,
            "imputation_method": stmt.excluded.imputation_method,
            "updated_at": sa.func.now(),
        }

        with self.engine.begin() as conn:
            result = conn.execute(
                stmt.on_conflict_do_update(
                    index_elements=["sensor_id", "ts", "version"],
                    set_=update_cols,
                )
            )
        return result.rowcount

    def fetch_raw_range(self, start, end) -> pd.DataFrame:
        df = pd.read_sql(
            RAW_RANGE_QUERY,
            self.engine,
            params={"start": start, "end": end},
        )
        if not df.empty:
            df["ts"] = pd.to_datetime(df["ts"], utc=True)
        return df

    def raw_time_bounds(self) -> Tuple[pd.Timestamp, pd.Timestamp] | Tuple[None, None]:
        with self.engine.begin() as conn:
            row = conn.execute(sa.text(BOUNDS_QUERY)).first()
        if not row or row.min_ts is None or row.max_ts is None:
            return None, None
        return pd.Timestamp(row.min_ts, tz="UTC"), pd.Timestamp(row.max_ts, tz="UTC")
