from __future__ import annotations

import json
import logging
from datetime import timezone

import numpy as np

from .config import load
from .contours import generate_contours_geojson
from .db import Database
from .grid_builder import GridBuilder
from .uploader import BlobUploader

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("etl")


def run():
    cfg = load()
    logger.info(
        "starting grid ETL (interval=%s, res=%sm, dry_run=%s)",
        cfg.grid_interval,
        cfg.grid_resolution_m,
        cfg.dry_run,
    )

    db = Database(cfg)
    builder = GridBuilder(cfg.grid_resolution_m, cfg.grid_padding_m)
    uploader = BlobUploader(cfg)

    db.ensure_slots()
    pending = db.fetch_pending_slots()
    if not pending:
        logger.info("no pending grid runs")
        return

    for run_id, slot in pending:
        logger.info("processing slot %s (id=%s)", slot.isoformat(), run_id)
        try:
            snapshot = db.load_snapshot(slot)
            if snapshot.empty:
                raise ValueError("no clean measurements for slot")

            artifact = builder.build(snapshot)

            timestamp = slot.strftime("%Y%m%dT%H%M%SZ")
            base_key = f"grids/{timestamp}"

            if cfg.dry_run:
                logger.info(
                    "dry-run: would upload artifacts for slot %s (grid shape %s)",
                    slot,
                    artifact.data_grid.shape,
                )
                db.mark_success(
                    run_id,
                    json.dumps(list(artifact.bbox_3857)),
                    npz_url="",
                    json_url="",
                    contours_url="",
                    message="dry-run",
                )
                continue

            npz_payload = {
                "data": artifact.data_grid.astype(np.float32),
                "x": artifact.x_coords.astype(np.float64),
                "y": artifact.y_coords.astype(np.float64),
                "metadata": np.array([artifact.metadata_json]),
            }
            npz_url = uploader.upload_npz(f"{base_key}/grid.npz", npz_payload)

            grid_json_url = uploader.upload_grid_json(
                f"{base_key}/grid.json.gz",
                artifact,
            )

            contour_bytes = generate_contours_geojson(
                artifact.x_coords,
                artifact.y_coords,
                artifact.data_grid,
                artifact.levels,
            )
            contours_url = uploader.upload_bytes(
                f"{base_key}/contours.geojson",
                contour_bytes,
                "application/geo+json",
            )

            latest_payload = {
                "timestamp": json.loads(artifact.metadata_json)["timestamp"],
                "grid_npz_url": npz_url,
                "grid_json_url": grid_json_url,
                "contours_url": contours_url,
                "res_m": cfg.grid_resolution_m,
                "bbox": json.loads(artifact.metadata_json)["bbox_wgs84"],
            }
            latest_url = uploader.upload_json("grids/latest.json", latest_payload)
            logger.info("updated latest pointer: %s", latest_url)

            db.mark_success(
                run_id,
                json.dumps(list(artifact.bbox_3857)),
                npz_url=npz_url,
                json_url=grid_json_url,
                contours_url=contours_url,
            )

            logger.info("slot %s processed: %s", slot.isoformat(), base_key)
        except Exception as exc:  # pragma: no cover
            logger.exception("slot %s failed", slot)
            db.mark_failure(run_id, str(exc))


def main():
    try:
        run()
    except Exception:  # pragma: no cover
        logger.exception("ETL execution failed")
        raise


if __name__ == "__main__":
    main()
