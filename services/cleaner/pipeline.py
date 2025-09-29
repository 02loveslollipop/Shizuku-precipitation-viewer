from __future__ import annotations

import logging

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingRegressor

from .config import Config

logger = logging.getLogger(__name__)

OUTLIER_FLAG = 1
IMPUTED_FLAG = 2
POOR_QUALITY_FLAG = 4


def clean_measurements(raw_df: pd.DataFrame, cfg: Config) -> pd.DataFrame:
    """Apply QC + forecasting-based imputation to raw measurements."""
    if raw_df.empty:
        return pd.DataFrame(columns=["sensor_id", "ts", "value_mm", "qc_flags", "imputation_method", "version"])

    results = []
    for sensor_id, group in raw_df.groupby("sensor_id"):
        cleaned = _clean_sensor_dataframe(sensor_id, group, cfg)
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

    if cfg.gbm_enabled:
        gbm_filled, gbm_labels = _gbm_forecast_fill(clean_series, cfg)
        newly_filled = clean_series.isna() & gbm_filled.notna()
        clean_series = gbm_filled
        imputation_method.loc[newly_filled] = gbm_labels.loc[newly_filled]

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
        base_series = clean_series.dropna()
        fallback = base_series.median() if not base_series.empty else None
        if pd.isna(fallback):
            fallback = cfg.min_value_mm
            logger.debug(
                "sensor %s: using fallback %.3f for %d gaps",
                sensor_id,
                fallback,
                remaining.sum(),
            )
        clean_series.loc[remaining] = fallback
        imputation_method.loc[remaining] = "global_median"

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


def _gbm_forecast_fill(series: pd.Series, cfg: Config) -> tuple[pd.Series, pd.Series]:
    filled = series.copy().astype(float)
    labels = pd.Series(index=series.index, dtype="object")

    feature_cols = ["lag1", "lag2", "lag3", "hour", "dow", "month"]

    def build_features(values: pd.Series) -> pd.DataFrame:
        return pd.DataFrame(
            {
                "lag1": values.shift(1),
                "lag2": values.shift(2),
                "lag3": values.shift(3),
                "hour": values.index.hour,
                "dow": values.index.dayofweek,
                "month": values.index.month,
            },
            index=values.index,
        )

    for _ in range(max(1, cfg.gbm_max_iters)):
        features = build_features(filled)
        train_mask = filled.notna()
        for col in ["lag1", "lag2", "lag3"]:
            train_mask &= features[col].notna()
        if train_mask.sum() < cfg.gbm_min_train:
            break

        model = HistGradientBoostingRegressor(
            max_depth=cfg.gbm_max_depth,
            learning_rate=cfg.gbm_learning_rate,
            random_state=cfg.gbm_random_state,
        )
        model.fit(features.loc[train_mask, feature_cols], filled.loc[train_mask])

        pred_mask = filled.isna()
        progress = False
        for ts in filled.index[pred_mask]:
            x = features.loc[ts, feature_cols]
            if x.isna().any():
                continue
            pred = float(model.predict([x.values])[0])
            pred = float(np.clip(pred, cfg.min_value_mm, cfg.max_value_mm))
            filled.loc[ts] = pred
            labels.loc[ts] = "gbm_forecast"
            progress = True

        if not progress:
            break

    return filled, labels
