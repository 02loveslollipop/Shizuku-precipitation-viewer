"""
Unit tests for ETL aggregate calculation functions.

Tests the aggregate_sensor_data function that computes
min, max, avg, and count for each sensor during a grid period.
"""

import unittest
from datetime import datetime, timedelta
import sys
import os
import pandas as pd

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from aggregates import aggregate_sensor_data, calculate_avg_mm_h


class TestAggregateSensorData(unittest.TestCase):
    """Test suite for aggregate calculation logic."""

    def test_single_sensor_single_measurement(self):
        """Test aggregate calculation with one sensor and one measurement."""
        df = pd.DataFrame([
            {'sensor_id': 'SENSOR_001', 'ts': datetime(2025, 10, 3, 12, 0, 0), 'value_mm': 5.0}
        ])
        interval = pd.Timedelta(minutes=30)  # 30-minute gap
        
        result = aggregate_sensor_data(df, interval)
        
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['sensor_id'], 'SENSOR_001')
        self.assertEqual(result[0]['avg_mm_h'], 10.0)  # 5mm / 0.5h = 10mm/h
        self.assertEqual(result[0]['min_value_mm'], 5.0)
        self.assertEqual(result[0]['max_value_mm'], 5.0)
        self.assertEqual(result[0]['measurement_count'], 1)

    def test_single_sensor_multiple_measurements(self):
        """Test aggregate calculation with one sensor and multiple measurements."""
        df = pd.DataFrame([
            {'sensor_id': 'SENSOR_001', 'ts': datetime(2025, 10, 3, 12, 0, 0), 'value_mm': 2.0},
            {'sensor_id': 'SENSOR_001', 'ts': datetime(2025, 10, 3, 12, 15, 0), 'value_mm': 4.0},
            {'sensor_id': 'SENSOR_001', 'ts': datetime(2025, 10, 3, 12, 30, 0), 'value_mm': 6.0},
        ])
        interval = pd.Timedelta(minutes=60)  # 60-minute gap
        
        result = aggregate_sensor_data(df, interval)
        
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['sensor_id'], 'SENSOR_001')
        # Average of 2, 4, 6 is 4mm, divided by 1 hour = 4mm/h
        self.assertEqual(result[0]['avg_mm_h'], 4.0)
        self.assertEqual(result[0]['min_value_mm'], 2.0)
        self.assertEqual(result[0]['max_value_mm'], 6.0)
        self.assertEqual(result[0]['measurement_count'], 3)

    def test_multiple_sensors(self):
        """Test aggregate calculation with multiple sensors."""
        df = pd.DataFrame([
            {'sensor_id': 'SENSOR_001', 'ts': datetime(2025, 10, 3, 12, 0, 0), 'value_mm': 3.0},
            {'sensor_id': 'SENSOR_001', 'ts': datetime(2025, 10, 3, 12, 30, 0), 'value_mm': 6.0},
            {'sensor_id': 'SENSOR_002', 'ts': datetime(2025, 10, 3, 12, 0, 0), 'value_mm': 2.0},
            {'sensor_id': 'SENSOR_002', 'ts': datetime(2025, 10, 3, 12, 30, 0), 'value_mm': 4.0},
        ])
        interval = pd.Timedelta(minutes=60)
        
        result = aggregate_sensor_data(df, interval)
        
        self.assertEqual(len(result), 2)
        
        # Find each sensor's result
        sensor_001 = next(r for r in result if r['sensor_id'] == 'SENSOR_001')
        sensor_002 = next(r for r in result if r['sensor_id'] == 'SENSOR_002')
        
        self.assertEqual(sensor_001['avg_mm_h'], 4.5)  # (3+6)/2 / 1h = 4.5mm/h
        self.assertEqual(sensor_001['measurement_count'], 2)
        
        self.assertEqual(sensor_002['avg_mm_h'], 3.0)  # (2+4)/2 / 1h = 3.0mm/h
        self.assertEqual(sensor_002['measurement_count'], 2)

    def test_zero_measurements(self):
        """Test handling of zero mm measurements."""
        df = pd.DataFrame([
            {'sensor_id': 'SENSOR_001', 'ts': datetime(2025, 10, 3, 12, 0, 0), 'value_mm': 0.0},
            {'sensor_id': 'SENSOR_001', 'ts': datetime(2025, 10, 3, 12, 30, 0), 'value_mm': 0.0},
        ])
        interval = pd.Timedelta(minutes=60)
        
        result = aggregate_sensor_data(df, interval)
        
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['avg_mm_h'], 0.0)
        self.assertEqual(result[0]['min_value_mm'], 0.0)
        self.assertEqual(result[0]['max_value_mm'], 0.0)

    def test_empty_measurements(self):
        """Test handling of empty measurement DataFrame."""
        df = pd.DataFrame(columns=['sensor_id', 'ts', 'value_mm'])
        interval = pd.Timedelta(minutes=60)
        
        result = aggregate_sensor_data(df, interval)
        
        self.assertEqual(result, [])

    def test_different_intervals(self):
        """Test mm to mm/h conversion for different interval durations."""
        # Test 30-minute interval
        df_30min = pd.DataFrame([
            {'sensor_id': 'SENSOR_001', 'ts': datetime(2025, 10, 3, 12, 0, 0), 'value_mm': 5.0}
        ])
        result_30min = aggregate_sensor_data(df_30min, pd.Timedelta(minutes=30))
        self.assertEqual(result_30min[0]['avg_mm_h'], 10.0)  # 5mm / 0.5h = 10mm/h
        
        # Test 15-minute interval
        df_15min = pd.DataFrame([
            {'sensor_id': 'SENSOR_001', 'ts': datetime(2025, 10, 3, 12, 0, 0), 'value_mm': 5.0}
        ])
        result_15min = aggregate_sensor_data(df_15min, pd.Timedelta(minutes=15))
        self.assertEqual(result_15min[0]['avg_mm_h'], 20.0)  # 5mm / 0.25h = 20mm/h


class TestCalculateAvgMmH(unittest.TestCase):
    """Test suite for average mm/h calculation."""

    def test_basic_calculation(self):
        """Test basic average calculation."""
        values = pd.Series([2.0, 4.0, 6.0])
        interval_hours = 1.0
        
        result = calculate_avg_mm_h(values, interval_hours)
        
        self.assertEqual(result, 4.0)  # (2+4+6)/3 / 1h = 4mm/h

    def test_empty_series(self):
        """Test handling of empty series."""
        values = pd.Series([])
        interval_hours = 1.0
        
        result = calculate_avg_mm_h(values, interval_hours)
        
        self.assertEqual(result, 0.0)

    def test_zero_interval(self):
        """Test handling of zero interval."""
        values = pd.Series([5.0])
        interval_hours = 0.0
        
        result = calculate_avg_mm_h(values, interval_hours)
        
        self.assertEqual(result, 0.0)

    def test_fractional_interval(self):
        """Test with fractional hour interval."""
        values = pd.Series([3.0])
        interval_hours = 0.5  # 30 minutes
        
        result = calculate_avg_mm_h(values, interval_hours)
        
        self.assertEqual(result, 6.0)  # 3mm / 0.5h = 6mm/h


if __name__ == '__main__':
    unittest.main()
