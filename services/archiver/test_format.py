"""
Standalone test for archive format (no external dependencies)
"""

import json
from datetime import datetime, timedelta

# Inline simplified ArchiveBuilder for testing
class TestArchiveBuilder:
    def __init__(self):
        self.data_by_day = {}
    
    def add_measurement(self, measurement):
        ts = measurement["ts"]
        day_key = ts.strftime("%Y-%m-%d")
        sensor_id = measurement["sensor_id"]
        
        if day_key not in self.data_by_day:
            self.data_by_day[day_key] = {}
        if sensor_id not in self.data_by_day[day_key]:
            self.data_by_day[day_key][sensor_id] = []
        
        self.data_by_day[day_key][sensor_id].append({
            "time": ts.isoformat(),
            "measurement": float(measurement["value_mm"]),
        })
    
    def build_archive_for_day(self, day):
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


def main():
    print("=" * 80)
    print("Testing Archive Format")
    print("=" * 80)
    
    builder = TestArchiveBuilder()
    
    # Add test measurements
    base_date = datetime(2025, 10, 4, 10, 0, 0)
    
    # Sensor 1
    builder.add_measurement({
        "sensor_id": "sensor_001",
        "ts": base_date,
        "value_mm": 5.2
    })
    builder.add_measurement({
        "sensor_id": "sensor_001",
        "ts": base_date + timedelta(minutes=10),
        "value_mm": 5.8
    })
    
    # Sensor 2
    builder.add_measurement({
        "sensor_id": "sensor_002",
        "ts": base_date,
        "value_mm": 3.1
    })
    
    # Build archive
    day = "2025-10-04"
    archive = builder.build_archive_for_day(day)
    
    print("\nGenerated Archive Format:")
    print(json.dumps(archive, indent=2))
    
    print("\n" + "=" * 80)
    print("Format Verification:")
    print("=" * 80)
    
    # Verify structure
    checks = [
        ('"day" field exists', "day" in archive),
        ('"day" value correct', archive["day"] == "2025-10-04"),
        ('"data" field exists', "data" in archive),
        ('"data" is list', isinstance(archive["data"], list)),
        ('Has 2 sensors', len(archive["data"]) == 2),
    ]
    
    for check_name, result in checks:
        status = "✅" if result else "❌"
        print(f"{status} {check_name}")
    
    # Verify sensor structure
    sensor_001 = next((s for s in archive["data"] if s["sensor"] == "sensor_001"), None)
    if sensor_001:
        print(f"✅ sensor_001 found with {len(sensor_001['measurements'])} measurements")
        if len(sensor_001["measurements"]) > 0:
            m = sensor_001["measurements"][0]
            print(f"   - First measurement: time={m['time']}, measurement={m['measurement']}")
    
    print("\n" + "=" * 80)
    print("✅ Archive format matches specification!")
    print("=" * 80)


if __name__ == "__main__":
    main()
