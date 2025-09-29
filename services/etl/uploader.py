from __future__ import annotations

import gzip
import json
from io import BytesIO

import numpy as np
import vercel_blob

from .config import Config


class BlobUploader:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        # vercel_blob expects the token via environment variable
        import os

        os.environ["BLOB_READ_WRITE_TOKEN"] = cfg.blob_token

    def _resolve_url(self, info: dict, fallback_key: str) -> str:
        url = info.get("url") or info.get("downloadUrl")
        if url:
            return url
        pathname = info.get("pathname") or fallback_key
        return f"{self.cfg.blob_base_url}/{pathname.lstrip('/')}"

    def upload_bytes(self, key: str, data: bytes, content_type: str) -> str:
        info = vercel_blob.put(key, data, {"contentType": content_type, "allowOverwrite": True})
        return self._resolve_url(info, key)

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

        metadata = json.loads(grid_artifacts.metadata_json)
        payload = {
            "timestamp": metadata["timestamp"],
            "res_m": metadata["res_m"],
            "bbox_3857": metadata["bbox_3857"],
            "bbox_wgs84": metadata["bbox_wgs84"],
            "intensity_classes": metadata.get("intensity_classes", []),
            "intensity_thresholds": metadata.get("intensity_thresholds", []),
            "x": grid_artifacts.x_coords.tolist(),
            "y": grid_artifacts.y_coords.tolist(),
            "data": grid_artifacts.data_grid.astype(np.float32).tolist(),
        }
        data = gzip.compress(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
        return self.upload_bytes(key, data, "application/json+gzip")
