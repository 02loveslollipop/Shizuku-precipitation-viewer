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
from .aggregates import calculate_grid_sensor_aggregates

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
                    json_url="",
                    contours_url="",
                    message="dry-run",
                )
                continue

            # Upload grid JSON
            grid_json_url = uploader.upload_grid_json(
                f"{base_key}/grid.json.gz",
                artifact,
            )

            # Upload contours GeoJSON
            contour_bytes = generate_contours_geojson(
                artifact.x_coords,
                artifact.y_coords,
                artifact.data_grid,
                artifact.thresholds,
            )
            contours_url = uploader.upload_bytes(
                f"{base_key}/contours.geojson",
                contour_bytes,
                "application/geo+json",
            )

            # Upload JPEG preview if available
            jpeg_url = None
            if getattr(artifact, 'jpeg_bytes', None):
                try:
                    jpeg_url = uploader.upload_bytes(
                        f"{base_key}/preview.jpg", 
                        artifact.jpeg_bytes, 
                        "image/jpeg"
                    )
                    logger.info("uploaded JPEG preview: %s", jpeg_url)
                except Exception as exc:
                    logger.warning("failed to upload JPEG: %s", exc)
                    jpeg_url = None

            # Calculate sensor aggregates
            slot_end = slot + cfg.grid_interval
            aggregates = calculate_grid_sensor_aggregates(
                snapshot,
                ts_start=slot,
                ts_end=slot_end
            )
            
            # Insert aggregates into database
            if aggregates:
                for agg in aggregates:
                    agg['grid_run_id'] = run_id
                inserted_count = db.insert_sensor_aggregates(aggregates)
                logger.info("inserted %d sensor aggregates", inserted_count)
            else:
                logger.warning("no aggregates calculated for slot %s", slot.isoformat())

            # Update latest pointer (no .npz reference)
            metadata = json.loads(artifact.metadata_json)
            latest_payload = {
                "timestamp": metadata["timestamp"],
                "grid_json_url": grid_json_url,
                "grid_preview_jpeg_url": jpeg_url,
                "contours_url": contours_url,
                "res_m": cfg.grid_resolution_m,
                "bbox": metadata["bbox_wgs84"],
                "intensity_classes": metadata.get("intensity_classes", []),
                "intensity_thresholds": metadata.get("intensity_thresholds", []),
            }
            latest_url = uploader.upload_json("grids/latest.json", latest_payload)
            logger.info("updated latest pointer: %s", latest_url)

            # Mark grid run as successful
            db.mark_success(
                run_id,
                json.dumps(list(artifact.bbox_3857)),
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
