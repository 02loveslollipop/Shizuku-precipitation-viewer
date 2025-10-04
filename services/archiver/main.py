"""
Main entry point for the archiver service
"""

import logging
import sys
from datetime import datetime

from .archiver import run_archiver
from .config import load

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger(__name__)


def main():
    """Main entry point"""
    logger.info("=" * 80)
    logger.info("Starting Data Archiver Service")
    logger.info(f"Run time: {datetime.utcnow().isoformat()}")
    logger.info("=" * 80)
    
    try:
        cfg = load()
        
        logger.info(f"Configuration:")
        logger.info(f"  Raw retention: {cfg.raw_retention_days} days")
        logger.info(f"  Clean retention: {cfg.clean_retention_days} days")
        logger.info(f"  Batch size: {cfg.batch_size}")
        logger.info(f"  Dry run: {cfg.dry_run}")
        
        if cfg.dry_run:
            logger.warning("Running in DRY RUN mode - no data will be deleted or uploaded")
        
        stats = run_archiver(cfg)
        
        logger.info("=" * 80)
        logger.info("Archiver Service Complete")
        logger.info(f"Statistics:")
        logger.info(f"  Raw measurements deleted: {stats['raw_deleted']}")
        logger.info(f"  Clean measurements archived: {stats['clean_archived']}")
        logger.info(f"  Clean measurements deleted: {stats['clean_deleted']}")
        logger.info(f"  Archive files created: {stats['archives_created']}")
        logger.info("=" * 80)
        
        return 0
        
    except Exception as e:
        logger.error(f"Archiver service failed: {e}", exc_info=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
