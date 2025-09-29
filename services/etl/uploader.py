from __future__ import annotations

import gzip
import json
from io import BytesIO

import numpy as np
import requests

from .config import Config


class BlobUploader:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.session = requests.Session()
        self.session.headers.update({"Authorization": f"Bearer {cfg.blob_token}"})

    def upload_bytes(self, key: str, data: bytes, content_type: str) -> str:
        files = {
            "file": (key, data, content_type),
            "metadata": (None, json.dumps({"name": key}), "application/json"),
        }
        response = self.session.post(self.cfg.blob_api_url, files=files, timeout=60)
        response.raise_for_status()
        info = response.json()
        pathname = info.get("pathname") or key
        return f"{self.cfg.blob_base_url}/{pathname.lstrip('/')}"

    def upload_json(self, key: str, payload: dict) -> str:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        return self.upload_bytes(key, data, "application/json")

    def upload_npz(self, key: str, numpy_payload: dict) -> str:
        buffer = BytesIO()
        npz_data = {name: array for name, array in numpy_payload.items()}
        np.savez_compressed(buffer, **npz_data)
        return self.upload_bytes(key, buffer.getvalue(), "application/octet-stream")

    def upload_grid_json(self, key: str, grid_artifacts) -> str:
        import numpy as np

        payload = {
            "timestamp": json.loads(grid_artifacts.metadata_json)["timestamp"],
            "res_m": json.loads(grid_artifacts.metadata_json)["res_m"],
            "bbox_3857": json.loads(grid_artifacts.metadata_json)["bbox_3857"],
            "bbox_wgs84": json.loads(grid_artifacts.metadata_json)["bbox_wgs84"],
            "x": grid_artifacts.x_coords.tolist(),
            "y": grid_artifacts.y_coords.tolist(),
            "data": grid_artifacts.data_grid.astype(np.float32).tolist(),
        }
        data = gzip.compress(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
        return self.upload_bytes(key, data, "application/json+gzip")

