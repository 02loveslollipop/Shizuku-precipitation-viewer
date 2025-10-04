"""
Blob storage uploader for archives
"""

from __future__ import annotations

import logging
import os

import vercel_blob

from .config import ArchiverConfig

logger = logging.getLogger(__name__)


class ArchiveUploader:
    """Uploads archive files to blob storage"""
    
    def __init__(self, cfg: ArchiverConfig):
        self.cfg = cfg
        # Set token for vercel_blob library
        os.environ["BLOB_READ_WRITE_TOKEN"] = cfg.blob_token
    
    def _resolve_url(self, info: dict, fallback_key: str) -> str:
        """Resolve the final URL from blob upload response"""
        url = info.get("url") or info.get("downloadUrl")
        if url:
            return url
        pathname = info.get("pathname") or fallback_key
        return f"{self.cfg.blob_base_url}/{pathname.lstrip('/')}"
    
    def upload_archive(self, day: str, compressed_data: bytes) -> str:
        """
        Upload compressed archive to blob storage
        
        Args:
            day: Day in format YYYY-MM-DD
            compressed_data: Gzipped JSON data
            
        Returns:
            URL of uploaded blob
        """
        # Create blob key with path structure: archives/YYYY/MM/archive-YYYY-MM-DD.json.gz
        year, month, _ = day.split("-")
        key = f"archives/{year}/{month}/archive-{day}.json.gz"
        
        if self.cfg.dry_run:
            logger.info(f"[DRY RUN] Would upload {len(compressed_data)} bytes to {key}")
            return f"[dry-run]{key}"
        
        try:
            info = vercel_blob.put(
                key,
                compressed_data,
                {
                    "contentType": "application/json+gzip",
                    "allowOverwrite": True
                }
            )
            url = self._resolve_url(info, key)
            logger.info(f"Uploaded archive for {day} to {url} ({len(compressed_data)} bytes)")
            return url
        except Exception as e:
            logger.error(f"Failed to upload archive for {day}: {e}")
            raise
