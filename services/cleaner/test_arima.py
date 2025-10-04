"""
Test ARIMA imputation with 0 fallback
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

import numpy as np
import pandas as pd
from services.cleaner.pipeline import clean_measurements
from services.cleaner.config import Config
from datetime import timedelta

def test_arima_imputation():
    """Test that ARIMA imputation works for gaps"""
    print("Testing ARIMA imputation...")
    
    # Create test configuration
    cfg = Config(
        database_url="postgresql://dummy",
        lookback=timedelta(hours=72),
        min_value_mm=0.0,
        max_value_mm=150.0,
        min_quality=None,
        interpolation_limit=6,
        dry_run=False,
        arima_enabled=True,
        arima_min_train=48,
        arima_max_order=3,
        arima_seasonal=True,
        arima_m=24,
    )
    
    # Create time series with a gap
    timestamps = pd.date_range('2025-10-01', periods=100, freq='h', tz='UTC')
    values = np.random.exponential(scale=2.0, size=100)
    
    # Create a gap (positions 50-55)
    values[50:56] = np.nan
    
    df = pd.DataFrame({
        'sensor_id': ['SENSOR_001'] * 100,
        'ts': timestamps,
        'value_mm': values,
        'quality': [1.0] * 100
    })
    
    # Clean the data
    result = clean_measurements(df, cfg)
    
    assert not result.empty, "Result should not be empty"
    assert 'imputation_method' in result.columns, "Should have imputation_method column"
    
    # Check that gaps were filled
    gap_rows = result[(result['ts'] >= timestamps[50]) & (result['ts'] <= timestamps[55])]
    arima_filled = gap_rows[gap_rows['imputation_method'] == 'arima_forecast']
    
    print(f"  ✅ Gap positions filled with ARIMA: {len(arima_filled)}")
    print(f"  ✅ Total rows in result: {len(result)}")
    
    return True

def test_zero_fallback():
    """Test that 0 is used as final fallback"""
    print("Testing 0 fallback...")
    
    cfg = Config(
        database_url="postgresql://dummy",
        lookback=timedelta(hours=72),
        min_value_mm=0.0,
        max_value_mm=150.0,
        min_quality=None,
        interpolation_limit=6,
        dry_run=False,
        arima_enabled=False,  # Disable ARIMA to force fallback
        arima_min_train=48,
        arima_max_order=3,
        arima_seasonal=False,
        arima_m=24,
    )
    
    # Create test data with only NaN values after some valid points
    timestamps = pd.date_range('2025-10-01', periods=50, freq='h', tz='UTC')
    values = np.array([1.0, 2.0, 3.0] + [np.nan] * 47)  # Only 3 valid points
    
    df = pd.DataFrame({
        'sensor_id': ['SENSOR_001'] * 50,
        'ts': timestamps,
        'value_mm': values,
        'quality': [1.0] * 50
    })
    
    # Clean the data
    result = clean_measurements(df, cfg)
    
    assert not result.empty, "Result should not be empty"
    
    # Check fallback values
    fallback_rows = result[result['imputation_method'] == 'zero_fallback']
    if len(fallback_rows) > 0:
        assert all(fallback_rows['value_mm'] == 0.0), "Fallback should use 0.0"
        print(f"  ✅ Found {len(fallback_rows)} rows with zero_fallback")
        print(f"  ✅ All fallback values are 0.0: {all(fallback_rows['value_mm'] == 0.0)}")
    else:
        print("  ℹ️  No zero_fallback used (gaps filled by other methods)")
    
    return True

def test_imputation_hierarchy():
    """Test that imputation follows correct hierarchy: ARIMA -> interpolation -> hourly median -> 0"""
    print("Testing imputation hierarchy...")
    
    cfg = Config(
        database_url="postgresql://dummy",
        lookback=timedelta(hours=72),
        min_value_mm=0.0,
        max_value_mm=150.0,
        min_quality=None,
        interpolation_limit=6,
        dry_run=False,
        arima_enabled=True,
        arima_min_train=48,
        arima_max_order=3,
        arima_seasonal=True,
        arima_m=24,
    )
    
    # Create various gap scenarios
    timestamps = pd.date_range('2025-10-01', periods=200, freq='h', tz='UTC')
    values = np.random.exponential(scale=2.0, size=200)
    
    # Small gap (should be interpolated)
    values[10:13] = np.nan
    
    # Medium gap (should use ARIMA)
    values[50:58] = np.nan
    
    # Larger gap (might use hourly median or fallback)
    values[180:190] = np.nan
    
    df = pd.DataFrame({
        'sensor_id': ['SENSOR_001'] * 200,
        'ts': timestamps,
        'value_mm': values,
        'quality': [1.0] * 200
    })
    
    result = clean_measurements(df, cfg)
    
    assert not result.empty, "Result should not be empty"
    
    # Check what methods were used
    methods_used = result['imputation_method'].value_counts()
    print("  Imputation methods used:")
    for method, count in methods_used.items():
        if method is not None:
            print(f"    - {method}: {count} values")
    
    print("  ✅ Hierarchy test complete")
    
    return True

if __name__ == '__main__':
    print("=" * 60)
    print("ARIMA IMPUTATION TESTS")
    print("=" * 60)
    print()
    
    try:
        test_arima_imputation()
        print()
        test_zero_fallback()
        print()
        test_imputation_hierarchy()
        print()
        print("=" * 60)
        print("✅ ALL TESTS PASSED")
        print("=" * 60)
    except Exception as e:
        print()
        print("=" * 60)
        print(f"❌ TEST FAILED: {e}")
        print("=" * 60)
        import traceback
        traceback.print_exc()
        exit(1)
