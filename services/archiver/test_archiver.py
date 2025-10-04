"""
Test script for the archiver service

Run with: python -m archiver.test_archiver
"""

import json
import logging
from datetime import datetime, timedelta

from .archive_builder import ArchiveBuilder, compress_archive
from .config import ArchiverConfig

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def test_archive_builder():
    """Test the archive builder functionality"""
    logger.info("Testing ArchiveBuilder...")
    
    builder = ArchiveBuilder()
    
    # Add some test measurements
    base_time = datetime(2025, 1, 15, 0, 0, 0)
    
    # Sensor 1 - 3 measurements
    for i in range(3):
        builder.add_measurement({
            "sensor_id": "sensor_001",
            "ts": base_time + timedelta(minutes=i * 10),
            "value_mm": 5.0 + i * 0.5,
            "qc_flags": 0,
            "imputation_method": None
        })
    
    # Sensor 2 - 2 measurements
    for i in range(2):
        builder.add_measurement({
            "sensor_id": "sensor_002",
            "ts": base_time + timedelta(minutes=i * 10),
            "value_mm": 3.0 + i * 0.3,
            "qc_flags": 0,
            "imputation_method": "ARIMA"
        })
    
    # Next day - Sensor 1
    next_day = base_time + timedelta(days=1)
    builder.add_measurement({
        "sensor_id": "sensor_001",
        "ts": next_day,
        "value_mm": 8.5,
        "qc_flags": 1,
        "imputation_method": None
    })
    
    # Get all days
    days = builder.get_all_days()
    logger.info(f"Days with data: {days}")
    assert len(days) == 2, f"Expected 2 days, got {len(days)}"
    
    # Build archive for first day
    archive = builder.build_archive_for_day(days[0])
    
    # Verify structure
    assert "day" in archive, "Archive missing 'day' field"
    assert "data" in archive, "Archive missing 'data' field"
    assert isinstance(archive["data"], list), "Archive 'data' should be a list"
    
    logger.info(f"Archive for {days[0]}:")
    logger.info(json.dumps(archive, indent=2))
    
    # Verify sensors
    sensors_dict = {item["sensor"]: item for item in archive["data"]}
    assert "sensor_001" in sensors_dict, "sensor_001 not found"
    assert "sensor_002" in sensors_dict, "sensor_002 not found"
    
    # Verify measurements
    sensor_001_data = sensors_dict["sensor_001"]
    assert len(sensor_001_data["measurements"]) == 3, "sensor_001 should have 3 measurements"
    
    sensor_002_data = sensors_dict["sensor_002"]
    assert len(sensor_002_data["measurements"]) == 2, "sensor_002 should have 2 measurements"
    
    # Test compression
    compressed = compress_archive(archive)
    logger.info(f"Compressed size: {len(compressed)} bytes")
    logger.info(f"Original JSON size: {len(json.dumps(archive))} bytes")
    logger.info(f"Compression ratio: {len(json.dumps(archive)) / len(compressed):.2f}x")
    
    logger.info("✅ ArchiveBuilder tests passed!")


def test_archive_format():
    """Test that archive format matches specification"""
    logger.info("Testing archive format specification...")
    
    builder = ArchiveBuilder()
    
    # Create test data
    ts = datetime(2025, 10, 4, 12, 0, 0)
    builder.add_measurement({
        "sensor_id": "TEST_SENSOR",
        "ts": ts,
        "value_mm": 10.5,
        "qc_flags": 0,
        "imputation_method": None
    })
    
    day = ts.strftime("%Y-%m-%d")
    archive = builder.build_archive_for_day(day)
    
    # Verify exact format from specification
    assert archive["day"] == "2025-10-04"
    assert len(archive["data"]) == 1
    
    sensor_data = archive["data"][0]
    assert sensor_data["sensor"] == "TEST_SENSOR"
    assert len(sensor_data["measurements"]) == 1
    
    measurement = sensor_data["measurements"][0]
    assert "time" in measurement
    assert "measurement" in measurement
    assert measurement["measurement"] == 10.5
    
    logger.info("Archive structure:")
    logger.info(json.dumps(archive, indent=2))
    logger.info("✅ Archive format matches specification!")


def main():
    """Run all tests"""
    logger.info("=" * 80)
    logger.info("Running Archiver Tests")
    logger.info("=" * 80)
    
    try:
        test_archive_builder()
        print()
        test_archive_format()
        
        logger.info("=" * 80)
        logger.info("All tests passed! ✅")
        logger.info("=" * 80)
        
    except Exception as e:
        logger.error(f"Test failed: {e}", exc_info=True)
        raise


if __name__ == "__main__":
    main()
