"""
Database operations for the archiver service
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Optional

import psycopg2
import psycopg2.extras

from .config import ArchiverConfig

logger = logging.getLogger(__name__)


class ArchiveDatabase:
    """Database operations for archiving measurements"""
    
    def __init__(self, cfg: ArchiverConfig):
        self.cfg = cfg
        self.conn: Optional[psycopg2.extensions.connection] = None
    
    def connect(self) -> None:
        """Establish database connection"""
        if self.conn is None or self.conn.closed:
            self.conn = psycopg2.connect(
                self.cfg.database_url,
                cursor_factory=psycopg2.extras.RealDictCursor
            )
            logger.info("Connected to database")
    
    def close(self) -> None:
        """Close database connection"""
        if self.conn and not self.conn.closed:
            self.conn.close()
            logger.info("Closed database connection")
    
    def __enter__(self):
        self.connect()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
    
    def delete_old_raw_measurements(self, cutoff_date: datetime) -> int:
        """
        Delete raw measurements older than cutoff_date
        
        Args:
            cutoff_date: Delete measurements with ts < cutoff_date
            
        Returns:
            Number of rows deleted
        """
        if self.cfg.dry_run:
            # Count only, don't delete
            with self.conn.cursor() as cur:
                cur.execute(
                    "SELECT COUNT(*) as count FROM shizuku.raw_measurements WHERE ts < %s",
                    (cutoff_date,)
                )
                count = cur.fetchone()["count"]
                logger.info(f"[DRY RUN] Would delete {count} raw measurements")
                return count
        
        with self.conn.cursor() as cur:
            cur.execute(
                "DELETE FROM shizuku.raw_measurements WHERE ts < %s",
                (cutoff_date,)
            )
            deleted = cur.rowcount
            self.conn.commit()
            logger.info(f"Deleted {deleted} raw measurements older than {cutoff_date}")
            return deleted
    
    def fetch_clean_measurements_to_archive(
        self,
        start_date: datetime,
        end_date: datetime,
        batch_size: int = 1000,
        offset: int = 0
    ) -> list[dict]:
        """
        Fetch clean measurements to archive
        
        Args:
            start_date: Start of date range (inclusive)
            end_date: End of date range (exclusive)
            batch_size: Number of records to fetch
            offset: Offset for pagination
            
        Returns:
            List of measurement dictionaries
        """
        with self.conn.cursor() as cur:
            cur.execute(
                """
                SELECT 
                    sensor_id,
                    ts,
                    value_mm,
                    qc_flags,
                    imputation_method
                FROM shizuku.clean_measurements
                WHERE ts >= %s AND ts < %s
                ORDER BY ts, sensor_id
                LIMIT %s OFFSET %s
                """,
                (start_date, end_date, batch_size, offset)
            )
            return cur.fetchall()
    
    def get_date_range_for_archiving(self, cutoff_date: datetime) -> tuple[datetime, datetime]:
        """
        Get the date range of clean measurements to archive
        
        Args:
            cutoff_date: Archive measurements with ts < cutoff_date
            
        Returns:
            Tuple of (min_date, max_date) or (None, None) if no data
        """
        with self.conn.cursor() as cur:
            cur.execute(
                """
                SELECT 
                    MIN(ts) as min_ts,
                    MAX(ts) as max_ts
                FROM shizuku.clean_measurements
                WHERE ts < %s
                """,
                (cutoff_date,)
            )
            result = cur.fetchone()
            if result["min_ts"] is None:
                return None, None
            return result["min_ts"], result["max_ts"]
    
    def delete_archived_measurements(
        self,
        start_date: datetime,
        end_date: datetime
    ) -> int:
        """
        Delete clean measurements that have been archived
        
        Args:
            start_date: Start of date range (inclusive)
            end_date: End of date range (exclusive)
            
        Returns:
            Number of rows deleted
        """
        if self.cfg.dry_run:
            with self.conn.cursor() as cur:
                cur.execute(
                    "SELECT COUNT(*) as count FROM shizuku.clean_measurements WHERE ts >= %s AND ts < %s",
                    (start_date, end_date)
                )
                count = cur.fetchone()["count"]
                logger.info(f"[DRY RUN] Would delete {count} archived clean measurements")
                return count
        
        with self.conn.cursor() as cur:
            cur.execute(
                "DELETE FROM shizuku.clean_measurements WHERE ts >= %s AND ts < %s",
                (start_date, end_date)
            )
            deleted = cur.rowcount
            self.conn.commit()
            logger.info(f"Deleted {deleted} archived clean measurements")
            return deleted
    
    def count_measurements_to_archive(self, cutoff_date: datetime) -> int:
        """Count how many clean measurements need to be archived"""
        with self.conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) as count FROM shizuku.clean_measurements WHERE ts < %s",
                (cutoff_date,)
            )
            return cur.fetchone()["count"]
