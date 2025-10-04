"""
Grid Sensor Aggregates Calculator

This module calculates sensor aggregates for grid periods.
Part of the Backend Refactoring v1 (October 2025).

Aggregates include:
- avg_mm_h: Average precipitation rate in mm/hour
- measurement_count: Number of measurements used
- min_value_mm: Minimum value in the period
- max_value_mm: Maximum value in the period
"""

from __future__ import annotations

import logging
from typing import Dict, List

import pandas as pd

logger = logging.getLogger("etl.aggregates")


def calculate_avg_mm_h(values: pd.Series, interval_hours: float) -> float:
    """
    Calculate average precipitation rate in mm/hour.
    
    Args:
        values: Series of precipitation values in mm
        interval_hours: Duration of the period in hours
        
    Returns:
        Average precipitation rate in mm/hour
    """
    if len(values) == 0 or interval_hours == 0:
        return 0.0
    
    avg_mm = values.mean()
    # Convert to rate: mm/hour
    # avg_mm is the average accumulated in the period
    # We divide by period duration to get rate
    avg_mm_h = avg_mm / interval_hours
    
    return float(avg_mm_h)


def aggregate_sensor_data(
    measurements_df: pd.DataFrame,
    interval: pd.Timedelta
) -> List[Dict]:
    """
    Aggregate sensor data for a grid period.
    
    Args:
        measurements_df: DataFrame with columns [sensor_id, ts, value_mm]
        interval: Duration of the grid period
        
    Returns:
        List of aggregate dictionaries, one per sensor
    """
    if measurements_df.empty:
        logger.warning("No measurements provided for aggregation")
        return []
    
    interval_hours = interval.total_seconds() / 3600
    
    aggregates = []
    
    # Group by sensor and calculate aggregates
    for sensor_id, sensor_data in measurements_df.groupby('sensor_id'):
        if len(sensor_data) == 0:
            continue
            
        values = sensor_data['value_mm']
        
        # Calculate average rate
        avg_mm_h = calculate_avg_mm_h(values, interval_hours)
        
        aggregate = {
            'sensor_id': sensor_id,
            'avg_mm_h': avg_mm_h,
            'measurement_count': len(sensor_data),
            'min_value_mm': float(values.min()),
            'max_value_mm': float(values.max()),
        }
        
        aggregates.append(aggregate)
    
    logger.info(f"Calculated aggregates for {len(aggregates)} sensors")
    
    return aggregates


def validate_aggregate(aggregate: Dict) -> bool:
    """
    Validate an aggregate dictionary.
    
    Args:
        aggregate: Aggregate dictionary to validate
        
    Returns:
        True if valid, False otherwise
    """
    required_fields = [
        'sensor_id', 'avg_mm_h', 'measurement_count', 
        'min_value_mm', 'max_value_mm'
    ]
    
    # Check all required fields present
    if not all(field in aggregate for field in required_fields):
        logger.error(f"Missing required fields in aggregate: {aggregate}")
        return False
    
    # Check numeric fields are valid
    if aggregate['avg_mm_h'] < 0:
        logger.warning(f"Negative avg_mm_h for sensor {aggregate['sensor_id']}: {aggregate['avg_mm_h']}")
        return False
        
    if aggregate['measurement_count'] <= 0:
        logger.error(f"Invalid measurement count for sensor {aggregate['sensor_id']}: {aggregate['measurement_count']}")
        return False
    
    if aggregate['min_value_mm'] > aggregate['max_value_mm']:
        logger.error(f"Min > Max for sensor {aggregate['sensor_id']}: {aggregate['min_value_mm']} > {aggregate['max_value_mm']}")
        return False
    
    return True


def calculate_grid_sensor_aggregates(
    snapshot_df: pd.DataFrame,
    ts_start: pd.Timestamp,
    ts_end: pd.Timestamp
) -> List[Dict]:
    """
    Calculate sensor aggregates for a grid period.
    
    This is the main entry point for aggregate calculation.
    
    Args:
        snapshot_df: DataFrame with sensor measurements [sensor_id, ts, value_mm]
        ts_start: Start of the grid period
        ts_end: End of the grid period
        
    Returns:
        List of aggregate dictionaries ready for database insertion
    """
    if snapshot_df.empty:
        logger.warning("Empty snapshot dataframe provided")
        return []
    
    interval = ts_end - ts_start
    
    # Calculate aggregates
    aggregates = aggregate_sensor_data(snapshot_df, interval)
    
    # Add timestamp information
    for aggregate in aggregates:
        aggregate['ts_start'] = ts_start
        aggregate['ts_end'] = ts_end
    
    # Validate all aggregates
    valid_aggregates = [agg for agg in aggregates if validate_aggregate(agg)]
    
    if len(valid_aggregates) < len(aggregates):
        logger.warning(
            "Filtered out %d invalid aggregates",
            len(aggregates) - len(valid_aggregates)
        )
    
    return valid_aggregates
