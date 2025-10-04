from __future__ import annotations

import logging
import warnings

import numpy as np
import pandas as pd
from statsmodels.tsa.arima.model import ARIMA

from .config import Config

logger = logging.getLogger(__name__)

OUTLIER_FLAG = 1
IMPUTED_FLAG = 2
POOR_QUALITY_FLAG = 4


def _aggregate_10min_windows(sensor_id: str, df: pd.DataFrame) -> pd.DataFrame:
    """Aggregate measurements into 10-minute windows, taking the maximum value.
    
    This reduces data bloat by consolidating multiple measurements within
    each 10-minute period into a single maximum value, which is appropriate
    for precipitation data where we care about peak intensity.
    
    Args:
        sensor_id: The sensor identifier
        df: DataFrame with columns: sensor_id, ts, value_mm, quality (optional)
        
    Returns:
        Aggregated DataFrame with one row per 10-minute window
    """
    if df.empty:
        return df
    
    # Ensure ts is datetime
    df = df.copy()
    df['ts'] = pd.to_datetime(df['ts'], utc=True)
    df = df.sort_values('ts')
    
    # Set ts as index for resampling
    df_indexed = df.set_index('ts')
    
    # Resample to 10-minute windows, taking max value_mm
    # For quality, take the mean (if present)
    agg_dict = {'value_mm': 'max'}
    if 'quality' in df_indexed.columns:
        agg_dict['quality'] = 'mean'
    
    resampled = df_indexed.resample('10T').agg(agg_dict)
    
    # Drop windows with no data
    resampled = resampled.dropna(subset=['value_mm'])
    
    if resampled.empty:
        return pd.DataFrame(columns=['sensor_id', 'ts', 'value_mm', 'quality', 'variable', 'source'])
    
    # Reset index to get ts back as column
    result = resampled.reset_index()
    result['sensor_id'] = sensor_id
    
    # Preserve other columns if they exist (use first value in window)
    if 'variable' in df.columns:
        result['variable'] = df['variable'].iloc[0]
    if 'source' in df.columns:
        result['source'] = df['source'].iloc[0]
    
    logger.debug(
        "sensor %s: aggregated %d measurements into %d 10-minute windows",
        sensor_id, len(df), len(result)
    )
    
    return result


def clean_measurements(raw_df: pd.DataFrame, cfg: Config) -> pd.DataFrame:
    """Apply QC + forecasting-based imputation to raw measurements.
    
    Aggregates measurements into 10-minute windows, taking the maximum value
    per sensor to reduce data bloat while maintaining temporal resolution.
    """
    if raw_df.empty:
        return pd.DataFrame(columns=["sensor_id", "ts", "value_mm", "qc_flags", "imputation_method", "version"])

    results = []
    for sensor_id, group in raw_df.groupby("sensor_id"):
        # First aggregate raw data by 10-minute windows
        aggregated = _aggregate_10min_windows(sensor_id, group)
        if aggregated.empty:
            continue
        # Then apply cleaning and imputation
        cleaned = _clean_sensor_dataframe(sensor_id, aggregated, cfg)
        if not cleaned.empty:
            results.append(cleaned)
    if not results:
        return pd.DataFrame(columns=["sensor_id", "ts", "value_mm", "qc_flags", "imputation_method", "version"])
    return pd.concat(results, ignore_index=True)


def _clean_sensor_dataframe(sensor_id: str, df: pd.DataFrame, cfg: Config) -> pd.DataFrame:
    df = df.sort_values("ts").reset_index(drop=True)
    ts_index = pd.to_datetime(df["ts"], utc=True)

    values = pd.to_numeric(df["value_mm"], errors="coerce")
    clean_series = pd.Series(values.to_numpy(dtype=float), index=ts_index, dtype=float)

    qc_flags = np.zeros(len(df), dtype=np.int32)

    outlier_mask = (clean_series < cfg.min_value_mm) | (clean_series > cfg.max_value_mm)
    clean_series[outlier_mask] = np.nan
    qc_flags[outlier_mask.to_numpy()] |= OUTLIER_FLAG

    if cfg.min_quality is not None and "quality" in df:
        quality = pd.to_numeric(df["quality"], errors="coerce")
        poor_quality_mask = quality < cfg.min_quality
        poor_quality_mask = poor_quality_mask.fillna(False)
        if poor_quality_mask.any():
            clean_series[poor_quality_mask.to_numpy()] = np.nan
            qc_flags[poor_quality_mask.to_numpy()] |= POOR_QUALITY_FLAG

    imputation_method = pd.Series(index=clean_series.index, dtype="object")

    if cfg.arima_enabled:
        arima_filled, arima_labels = _arima_forecast_fill(clean_series, cfg)
        newly_filled = clean_series.isna() & arima_filled.notna()
        clean_series = arima_filled
        imputation_method.loc[newly_filled] = arima_labels.loc[newly_filled]

    remaining = clean_series.isna()
    if remaining.any():
        interp = clean_series.interpolate(
            method="time",
            limit=cfg.interpolation_limit,
            limit_direction="both",
        )
        interp_filled = remaining & interp.notna()
        if interp_filled.any():
            clean_series.loc[interp_filled] = interp.loc[interp_filled]
            imputation_method.loc[interp_filled] = "time_interp"
        remaining = clean_series.isna()

    if remaining.any():
        base_series = clean_series.dropna()
        if not base_series.empty:
            hourly_medians = base_series.groupby(base_series.index.hour).median()
            for hour, median in hourly_medians.items():
                if pd.isna(median):
                    continue
                hour_mask = remaining & (clean_series.index.hour == hour)
                if hour_mask.any():
                    clean_series.loc[hour_mask] = median
                    imputation_method.loc[hour_mask] = "hour_median"
            remaining = clean_series.isna()
        else:
            logger.debug("sensor %s: no base data for hourly medians", sensor_id)

    if remaining.any():
        # Final fallback: use 0 (no precipitation)
        fallback = 0.0
        logger.debug(
            "sensor %s: using fallback %.3f for %d gaps",
            sensor_id,
            fallback,
            remaining.sum(),
        )
        clean_series.loc[remaining] = fallback
        imputation_method.loc[remaining] = "zero_fallback"

    clean_series = clean_series.clip(lower=cfg.min_value_mm, upper=cfg.max_value_mm)

    imputed_mask = imputation_method.notna()
    qc_flags[imputed_mask.to_numpy()] |= IMPUTED_FLAG

    valid_mask = ~clean_series.isna()
    if not valid_mask.any():
        return pd.DataFrame(columns=["sensor_id", "ts", "value_mm", "qc_flags", "imputation_method", "version"])

    qc_flags_series = pd.Series(qc_flags, index=clean_series.index)
    imputation_method = imputation_method.where(imputation_method.notna(), None)

    result = pd.DataFrame(
        {
            "sensor_id": sensor_id,
            "ts": clean_series.index,
            "value_mm": clean_series.values,
            "qc_flags": qc_flags_series.values,
            "imputation_method": imputation_method.values,
            "version": 1,
        }
    )

    result = result[valid_mask.values].reset_index(drop=True)
    return result


def _arima_forecast_fill(series: pd.Series, cfg: Config) -> tuple[pd.Series, pd.Series]:
    """Fill missing values using ARIMA forecasting."""
    filled = series.copy().astype(float)
    labels = pd.Series(index=series.index, dtype="object")

    # Need sufficient training data
    train_mask = filled.notna()
    if train_mask.sum() < cfg.arima_min_train:
        logger.debug("Insufficient data for ARIMA (%d < %d)", train_mask.sum(), cfg.arima_min_train)
        return filled, labels

    # Get indices of gaps to fill
    gap_mask = filled.isna()
    if not gap_mask.any():
        return filled, labels

    # Train ARIMA model on available data
    train_data = filled.dropna()
    
    try:
        # Suppress statsmodels warnings
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            
            # Use ARIMA with simple order (p, d, q)
            # For precipitation data: AR(1), I(1), MA(1) is a good starting point
            if cfg.arima_seasonal and len(train_data) >= cfg.arima_m * 2:
                # SARIMA model
                model = ARIMA(
                    train_data.values,
                    order=(1, 1, 1),
                    seasonal_order=(1, 1, 1, cfg.arima_m),
                    enforce_stationarity=False,
                    enforce_invertibility=False,
                )
            else:
                # Simple ARIMA model
                model = ARIMA(
                    train_data.values,
                    order=(cfg.arima_max_order, 1, cfg.arima_max_order),
                    enforce_stationarity=False,
                    enforce_invertibility=False,
                )
            
            fitted_model = model.fit()
        
        # Fill gaps by forecasting
        filled_count = 0
        for idx in series.index[gap_mask]:
            # Find position in the series
            pos = series.index.get_loc(idx)
            
            # Determine how many steps ahead to forecast
            last_valid_idx = series.index[train_mask][-1]
            last_valid_pos = series.index.get_loc(last_valid_idx)
            steps = pos - last_valid_pos
            
            if steps <= 0:
                continue  # Can't forecast backwards
            
            if steps > 100:  # Don't forecast too far ahead
                continue
            
            try:
                # Make forecast
                forecast = fitted_model.forecast(steps=steps)
                pred_value = float(forecast.iloc[-1] if hasattr(forecast, 'iloc') else forecast[-1])
                
                # Clip to valid range
                pred_value = float(np.clip(pred_value, cfg.min_value_mm, cfg.max_value_mm))
                
                filled.loc[idx] = pred_value
                labels.loc[idx] = "arima_forecast"
                filled_count += 1
            except Exception as e:
                logger.debug("Failed to forecast for position %d: %s", pos, str(e))
                continue
            
        logger.debug("ARIMA filled %d gaps", filled_count)
        
    except Exception as e:
        logger.warning("ARIMA forecasting failed: %s", str(e))
    
    return filled, labels
