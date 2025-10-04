"""
Archive builder - converts measurements to JSON format for storage
"""

from __future__ import annotations

import gzip
import json
import logging
from collections import defaultdict
from datetime import datetime
from typing import Any

logger = logging.getLogger(__name__)


class ArchiveBuilder:
    """Builds JSON archives from measurement data"""
    
    def __init__(self):
        # Group measurements by day and sensor
        self.data_by_day: dict[str, dict[str, list[dict]]] = defaultdict(lambda: defaultdict(list))
    
    def add_measurement(self, measurement: dict) -> None:
        """
        Add a measurement to the archive
        
        Args:
            measurement: Dict with keys: sensor_id, ts, value_mm, qc_flags, imputation_method
        """
        ts: datetime = measurement["ts"]
        day_key = ts.strftime("%Y-%m-%d")
        sensor_id = measurement["sensor_id"]
        
        self.data_by_day[day_key][sensor_id].append({
            "time": ts.isoformat(),
            "measurement": float(measurement["value_mm"]),
            "qc_flags": measurement.get("qc_flags", 0),
            "imputation_method": measurement.get("imputation_method"),
        })
    
    def build_archive_for_day(self, day: str) -> dict[str, Any]:
        """
        Build archive JSON for a specific day
        
        Args:
            day: Day key in format YYYY-MM-DD
            
        Returns:
            Archive JSON structure
        """
        sensors_data = []
        
        for sensor_id, measurements in self.data_by_day[day].items():
            sensors_data.append({
                "sensor": sensor_id,
                "measurements": measurements
            })
        
        return {
            "day": day,
            "data": sensors_data
        }
    
    def get_all_days(self) -> list[str]:
        """Get list of all days in the archive"""
        return sorted(self.data_by_day.keys())
    
    def clear(self) -> None:
        """Clear all accumulated data"""
        self.data_by_day.clear()


def compress_archive(archive_json: dict) -> bytes:
    """
    Compress archive JSON with gzip
    
    Args:
        archive_json: Archive dictionary to compress
        
    Returns:
        Gzipped JSON bytes
    """
    json_str = json.dumps(archive_json, separators=(",", ":"))
    return gzip.compress(json_str.encode("utf-8"))
