"""
Main archiver service logic
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Optional

from .archive_builder import ArchiveBuilder, compress_archive
from .config import ArchiverConfig
from .db import ArchiveDatabase
from .uploader import ArchiveUploader

logger = logging.getLogger(__name__)


class ArchiverService:
    """Main service for archiving old measurements"""
    
    def __init__(self, cfg: ArchiverConfig):
        self.cfg = cfg
        self.db = ArchiveDatabase(cfg)
        self.uploader = ArchiveUploader(cfg)
    
    def run(self) -> dict[str, int]:
        """
        Run the archiver service
        
        Returns:
            Dictionary with statistics:
            - raw_deleted: Number of raw measurements deleted
            - clean_archived: Number of clean measurements archived
            - clean_deleted: Number of clean measurements deleted
            - archives_created: Number of archive files created
        """
        stats = {
            "raw_deleted": 0,
            "clean_archived": 0,
            "clean_deleted": 0,
            "archives_created": 0,
        }
        
        with self.db:
            # Step 1: Delete old raw measurements
            logger.info("Step 1: Deleting old raw measurements...")
            raw_cutoff = datetime.utcnow() - timedelta(days=self.cfg.raw_retention_days)
            stats["raw_deleted"] = self.db.delete_old_raw_measurements(raw_cutoff)
            
            # Step 2: Archive old clean measurements
            logger.info("Step 2: Archiving old clean measurements...")
            clean_cutoff = datetime.utcnow() - timedelta(days=self.cfg.clean_retention_days)
            
            # Check if there's data to archive
            count = self.db.count_measurements_to_archive(clean_cutoff)
            if count == 0:
                logger.info("No clean measurements to archive")
                return stats
            
            logger.info(f"Found {count} clean measurements to archive")
            
            # Get date range
            min_date, max_date = self.db.get_date_range_for_archiving(clean_cutoff)
            if min_date is None:
                logger.info("No clean measurements found in date range")
                return stats
            
            logger.info(f"Archiving measurements from {min_date} to {max_date}")
            
            # Fetch and build archives day by day
            archive_results = self._archive_measurements(min_date, clean_cutoff)
            stats["clean_archived"] = archive_results["archived"]
            stats["archives_created"] = archive_results["archives_created"]
            
            # Step 3: Delete archived measurements
            if not self.cfg.dry_run and archive_results["archived"] > 0:
                logger.info("Step 3: Deleting archived measurements from database...")
                stats["clean_deleted"] = self.db.delete_archived_measurements(min_date, clean_cutoff)
            
        return stats
    
    def _archive_measurements(
        self,
        start_date: datetime,
        end_date: datetime
    ) -> dict[str, int]:
        """
        Archive measurements in the given date range
        
        Args:
            start_date: Start of range (inclusive)
            end_date: End of range (exclusive)
            
        Returns:
            Dict with 'archived' count and 'archives_created' count
        """
        builder = ArchiveBuilder()
        total_archived = 0
        archives_created = 0
        offset = 0
        
        while True:
            # Fetch batch of measurements
            measurements = self.db.fetch_clean_measurements_to_archive(
                start_date,
                end_date,
                batch_size=self.cfg.batch_size,
                offset=offset
            )
            
            if not measurements:
                break
            
            # Add to builder
            for measurement in measurements:
                builder.add_measurement(measurement)
                total_archived += 1
            
            offset += len(measurements)
            
            if len(measurements) < self.cfg.batch_size:
                break
        
        # Build and upload archives for each day
        for day in builder.get_all_days():
            archive = builder.build_archive_for_day(day)
            compressed = compress_archive(archive)
            
            try:
                url = self.uploader.upload_archive(day, compressed)
                archives_created += 1
                logger.info(f"Created archive for {day}: {url}")
            except Exception as e:
                logger.error(f"Failed to create archive for {day}: {e}")
                # Continue with other days
        
        return {
            "archived": total_archived,
            "archives_created": archives_created
        }


def run_archiver(cfg: Optional[ArchiverConfig] = None) -> dict[str, int]:
    """
    Run the archiver service
    
    Args:
        cfg: Configuration object (loads from env if not provided)
        
    Returns:
        Statistics dictionary
    """
    from .config import load
    
    if cfg is None:
        cfg = load()
    
    service = ArchiverService(cfg)
    return service.run()
