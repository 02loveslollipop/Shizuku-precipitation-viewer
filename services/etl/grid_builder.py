from __future__ import annotations

import json
import copy
from dataclasses import dataclass
from typing import List, Tuple, Optional

import numpy as np
from pyproj import Transformer
from scipy.signal import convolve2d
from scipy.interpolate import griddata

from matplotlib import cm, colors
import matplotlib.pyplot as plt
from io import BytesIO
from PIL import Image

@dataclass(slots=True)
class GridArtifacts:
    data_grid: np.ndarray
    x_coords: np.ndarray
    y_coords: np.ndarray
    bbox_3857: Tuple[float, float, float, float]
    bbox_wgs84: Tuple[float, float, float, float]
    metadata_json: str
    levels: np.ndarray
    thresholds: List[dict]
    intensity_classes: List[dict]
    jpeg_bytes: Optional[bytes]


INTENSITY_CLASSES = [
    {"label": "Trace", "min_mm": 0.0, "max_mm": 0.2, "description": "Trace precipitation (≤0.2 mm)"},
    {"label": "Light", "min_mm": 0.2, "max_mm": 2.5, "description": "Light precipitation (0.2–2.5 mm)"},
    {"label": "Moderate", "min_mm": 2.5, "max_mm": 7.6, "description": "Moderate precipitation (2.5–7.6 mm)"},
    {"label": "Heavy", "min_mm": 7.6, "max_mm": 50.0, "description": "Heavy precipitation (7.6–50 mm)"},
    {"label": "Violent", "min_mm": 50.0, "max_mm": None, "description": "Violent precipitation (>50 mm)"},
]


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

        # Create meshgrid in EPSG:3857 (x_grid, y_grid are in metres)
        xx, yy = np.meshgrid(x_grid, y_grid)

        # Prepare points for interpolation (sensor coordinates in 3857)
        points = np.column_stack((snapshot_df["x"].to_numpy(), snapshot_df["y"].to_numpy()))
        values = snapshot_df["value_mm"].to_numpy(dtype=float)

        grid_points = np.column_stack((xx.ravel(), yy.ravel()))

        # First attempt cubic (smooth quadratic-like) interpolation
        quad_flat = griddata(points, values, grid_points, method="cubic")

        # Fill any remaining gaps from cubic with nearest neighbour interpolation
        if np.any(np.isnan(quad_flat)):
            nearest_flat = griddata(points, values, grid_points, method="nearest")
            quad_flat[np.isnan(quad_flat)] = nearest_flat[np.isnan(quad_flat)]

        quad_grid = quad_flat.reshape(xx.shape)

        bbox_3857 = (float(min_x), float(min_y), float(max_x), float(max_y))
        west, south = self.to_wgs84.transform(min_x, min_y)
        east, north = self.to_wgs84.transform(max_x, max_y)
        bbox_wgs84 = (west, south, east, north)

        timestamp = snapshot_df["ts"].max().isoformat()

        thresholds = []
        for idx, cls in enumerate(INTENSITY_CLASSES):
            max_mm = cls["max_mm"]
            if max_mm is None:
                continue
            next_label = (
                INTENSITY_CLASSES[idx + 1]["label"]
                if idx + 1 < len(INTENSITY_CLASSES)
                else cls["label"]
            )
            thresholds.append(
                {
                    "value": float(max_mm),
                    "category": cls["label"],
                    "next_category": next_label,
                }
            )

        metadata = {
            "timestamp": timestamp,
            "res_m": self.res_m,
            "bbox_3857": bbox_3857,
            "bbox_wgs84": bbox_wgs84,
            "intensity_classes": copy.deepcopy(INTENSITY_CLASSES),
            "intensity_thresholds": thresholds,
        }

        if thresholds:
            levels = np.array([t["value"] for t in thresholds], dtype=float)
        else:
            levels = np.linspace(
                float(np.nanmin(quad_grid)),
                float(np.nanmax(quad_grid)),
                12,
            )

        # Also produce a compressed JPEG (RGB) for quick preview/storage. Convert colormap result
        # to RGB and encode as JPEG with reasonable quality to save space.
        try:
            # Render a matplotlib figure (pcolormesh + contours + colorbar) similarly to the
            # interactive notebook so the preview JPEG resembles the plotted output.
            fig, ax = plt.subplots(figsize=(10, 6))

            # pcolormesh expects x, y to be 1D grid coordinates
            mesh = ax.pcolormesh(x_coords, y_coords, quad_grid, cmap="viridis", shading="auto")
            # draw contour lines using computed levels (if available)
            try:
                contours = ax.contour(x_coords, y_coords, quad_grid, levels=levels, colors="white", linewidths=0.7)
                ax.clabel(contours, inline=True, fontsize=8, fmt="%.1f")
            except Exception:
                # If contouring fails for any reason, continue without labels
                pass

            ax.set_title("Quadratic Interpolated Grid (EPSG:3857)")
            ax.set_xlabel("x (m)")
            ax.set_ylabel("y (m)")

            # Add a colorbar to the figure
            fig.colorbar(mesh, ax=ax, label="Precipitation (mm)")
            plt.tight_layout()

            buf = BytesIO()
            # Save as JPEG using matplotlib's savefig (Pillow backend handles quality)
            fig.savefig(buf, format="jpeg", quality=70, optimize=True)
            jpeg_bytes = buf.getvalue()
            plt.close(fig)
        except Exception:
            jpeg_bytes = None

        return GridArtifacts(
            data_grid=quad_grid,
            x_coords=x_grid,
            y_coords=y_grid,
            bbox_3857=bbox_3857,
            bbox_wgs84=bbox_wgs84,
            metadata_json=json.dumps(metadata),
            levels=levels,
            thresholds=thresholds,
            intensity_classes=copy.deepcopy(INTENSITY_CLASSES),
            jpeg_bytes=jpeg_bytes,
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
