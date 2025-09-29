from __future__ import annotations

import json
from dataclasses import dataclass
from io import BytesIO
from typing import Dict, Tuple

import matplotlib.pyplot as plt
import numpy as np
from matplotlib import cm, colors
from pyproj import Transformer
from scipy.signal import convolve2d
from scipy.spatial import cKDTree

@dataclass(slots=True)
class GridArtifacts:
    data_grid: np.ndarray
    x_coords: np.ndarray
    y_coords: np.ndarray
    bbox_3857: Tuple[float, float, float, float]
    bbox_wgs84: Tuple[float, float, float, float]
    metadata_json: str
    png_rgba: np.ndarray
    levels: np.ndarray


class GridBuilder:
    def __init__(self, res_m: int, padding_m: int):
        self.res_m = res_m
        self.padding_m = padding_m
        self.to_3857 = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True)
        self.to_wgs84 = Transformer.from_crs("EPSG:3857", "EPSG:4326", always_xy=True)

    def build(self, snapshot_df) -> GridArtifacts:
        if snapshot_df.empty:
            raise ValueError("Snapshot dataframe is empty")

        x, y = self.to_3857.transform(snapshot_df["lon"].to_numpy(), snapshot_df["lat"].to_numpy())
        snapshot_df = snapshot_df.assign(x=x, y=y)

        min_x = snapshot_df["x"].min() - self.padding_m
        max_x = snapshot_df["x"].max() + self.padding_m
        min_y = snapshot_df["y"].min() - self.padding_m
        max_y = snapshot_df["y"].max() + self.padding_m

        nx = int(np.ceil((max_x - min_x) / self.res_m)) + 1
        ny = int(np.ceil((max_y - min_y) / self.res_m)) + 1

        x_grid = np.linspace(min_x, max_x, nx)
        y_grid = np.linspace(min_y, max_y, ny)

        seed_grid = np.full((ny, nx), np.nan, dtype=float)
        mask = np.zeros_like(seed_grid, dtype=bool)

        sensor_values = snapshot_df["value_mm"].to_numpy(dtype=float)
        xi = ((snapshot_df["x"] - min_x) / self.res_m).round().astype(int)
        yi = ((snapshot_df["y"] - min_y) / self.res_m).round().astype(int)

        for value, gx_raw, gy_raw in zip(sensor_values, xi, yi):
            gx = np.clip(gx_raw, 0, nx - 1)
            gy = np.clip(gy_raw, 0, ny - 1)
            if mask[gy, gx]:
                seed_grid[gy, gx] = np.nanmean([seed_grid[gy, gx], value])
            else:
                seed_grid[gy, gx] = value
                mask[gy, gx] = True

        kernel = self._lanczos_kernel(radius=4, a=4)
        seed_values = np.nan_to_num(seed_grid, nan=0.0)
        seed_mask = (~np.isnan(seed_grid)).astype(float)

        num = convolve2d(seed_values, kernel, mode="same", boundary="symm")
        den = convolve2d(seed_mask, kernel, mode="same", boundary="symm")

        lanczos_grid = np.where(den > 0, num / den, np.nan)

        remaining = np.isnan(lanczos_grid)
        if remaining.any():
            valid_idx = np.column_stack(np.where(~remaining))
            valid_vals = lanczos_grid[~remaining]
            tree = cKDTree(valid_idx)
            target_idx = np.column_stack(np.where(remaining))
            _dist, nn = tree.query(target_idx)
            lanczos_grid[remaining] = valid_vals[nn]

        bbox_3857 = (float(min_x), float(min_y), float(max_x), float(max_y))
        west, south = self.to_wgs84.transform(min_x, min_y)
        east, north = self.to_wgs84.transform(max_x, max_y)
        bbox_wgs84 = (west, south, east, north)

        timestamp = snapshot_df["ts"].max().isoformat()
        metadata = {
            "timestamp": timestamp,
            "res_m": self.res_m,
            "bbox_3857": bbox_3857,
            "bbox_wgs84": bbox_wgs84,
        }

        levels = np.linspace(float(np.nanmin(lanczos_grid)), float(np.nanmax(lanczos_grid)), 12)

        norm = colors.Normalize(vmin=np.nanmin(lanczos_grid), vmax=np.nanmax(lanczos_grid))
        rgba = cm.get_cmap("viridis")(norm(lanczos_grid))
        rgba[..., 3] = np.where(np.isnan(lanczos_grid), 0.0, 0.75)

        return GridArtifacts(
            data_grid=lanczos_grid,
            x_coords=x_grid,
            y_coords=y_grid,
            bbox_3857=bbox_3857,
            bbox_wgs84=bbox_wgs84,
            metadata_json=json.dumps(metadata),
            png_rgba=rgba,
            levels=levels,
        )

    @staticmethod
    def _lanczos_kernel(radius: int, a: int = 4) -> np.ndarray:
        x = np.arange(-radius, radius + 1, dtype=float)

        def lanczos(values):
            values = np.asarray(values, dtype=float)
            out = np.sinc(values) * np.sinc(values / a)
            out[np.abs(values) > a] = 0.0
            out[np.isnan(out)] = 1.0
            return out

        k1d = lanczos(x)
        kernel = np.outer(k1d, k1d)
        return kernel / kernel.sum()
