from __future__ import annotations

import matplotlib
matplotlib.use("Agg")

import json
from typing import List, Dict

import matplotlib.pyplot as plt
from pyproj import Transformer


def generate_contours_geojson(x_grid, y_grid, data_grid, thresholds: List[Dict]):
    if not thresholds:
        geojson = {"type": "FeatureCollection", "features": []}
        return json.dumps(geojson, separators=(",", ":")).encode("utf-8")

    levels = [t["value"] for t in thresholds]
    transformer = Transformer.from_crs("EPSG:3857", "EPSG:4326", always_xy=True)
    fig, ax = plt.subplots()
    try:
        contour_set = ax.contour(x_grid, y_grid, data_grid, levels=levels)
        features = []
        for threshold, segments in zip(thresholds, contour_set.allsegs):
            for seg in segments:
                if len(seg) < 2:
                    continue
                lon, lat = transformer.transform(seg[:, 0], seg[:, 1])
                coords = [[float(lon_val), float(lat_val)] for lon_val, lat_val in zip(lon, lat)]
                features.append(
                    {
                        "type": "Feature",
                        "properties": {
                            "threshold_mm": float(threshold["value"]),
                            "category": threshold["category"],
                            "next_category": threshold["next_category"],
                        },
                        "geometry": {"type": "LineString", "coordinates": coords},
                    }
                )
    finally:
        plt.close(fig)

    geojson = {"type": "FeatureCollection", "features": features}
    return json.dumps(geojson, separators=(",", ":")).encode("utf-8")
