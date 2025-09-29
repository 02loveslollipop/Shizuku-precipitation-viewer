from __future__ import annotations

import matplotlib
matplotlib.use('Agg')

import json
from typing import Iterable

import matplotlib.pyplot as plt
from matplotlib.contour import QuadContourSet
from pyproj import Transformer


def generate_contours_geojson(x_grid, y_grid, data_grid, levels: Iterable[float]):
    transformer = Transformer.from_crs("EPSG:3857", "EPSG:4326", always_xy=True)
    fig, ax = plt.subplots()
    try:
        contour_set: QuadContourSet = ax.contour(x_grid, y_grid, data_grid, levels=levels)
        features = []
        for level, collection in zip(contour_set.levels, contour_set.collections):
            for path in collection.get_paths():
                coords = path.vertices
                if len(coords) < 2:
                    continue
                lon, lat = transformer.transform(coords[:, 0], coords[:, 1])
                features.append(
                    {
                        "type": "Feature",
                        "properties": {"level": float(level)},
                        "geometry": {
                            "type": "LineString",
                            "coordinates": list(map(lambda pair: [pair[0], pair[1]], zip(lon, lat))),
                        },
                    }
                )
    finally:
        plt.close(fig)

    geojson = {"type": "FeatureCollection", "features": features}
    return json.dumps(geojson, separators=(",", ":")).encode("utf-8")
