#!/usr/bin/env python3
"""Migrate AES-encrypted templates to plain NPZ format.

Run this script BEFORE deploying code that removes crypto.py.
It reads all templates from the database, decrypts any that use
AES-256-GCM (EYED1 prefix), and re-writes them as plain NPZ blobs.

Usage:
    python scripts/migrate_aes_to_npz.py \
        --db-url postgresql://eyed:eyed_dev@localhost:9506/eyed \
        --encryption-key <64-hex-chars>

    # Dry run (count affected rows without modifying):
    python scripts/migrate_aes_to_npz.py \
        --db-url postgresql://eyed:eyed_dev@localhost:9506/eyed \
        --encryption-key <64-hex-chars> \
        --dry-run
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import logging
import sys

import asyncpg

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger(__name__)

# Blob format prefixes
_EYED1_PREFIX = b"EYED1"
_HEV1_PREFIX = b"HEv1"
_NPZ_MAGIC = b"PK\x03\x04"
_NONCE_SIZE = 12


def parse_key(raw: str) -> bytes:
    """Parse a 32-byte key from hex or base64 encoding."""
    raw = raw.strip()
    try:
        key_bytes = bytes.fromhex(raw)
    except ValueError:
        key_bytes = base64.b64decode(raw)
    if len(key_bytes) != 32:
        raise ValueError(
            f"Encryption key must be 32 bytes (got {len(key_bytes)}). "
            "Provide 64 hex chars or 44 base64 chars."
        )
    return key_bytes


def decrypt_aes(data: bytes, key: bytes) -> bytes:
    """Decrypt an EYED1-prefixed AES-256-GCM blob.

    This is a self-contained copy of the decrypt logic from crypto.py,
    so the migration script works even after crypto.py is deleted.
    """
    if not data or data[:5] != _EYED1_PREFIX:
        raise ValueError("Data does not have EYED1 prefix")

    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    nonce = data[5 : 5 + _NONCE_SIZE]
    ct_with_tag = data[5 + _NONCE_SIZE :]
    aesgcm = AESGCM(key)
    return aesgcm.decrypt(nonce, ct_with_tag, None)


def detect_format(data: bytes) -> str:
    """Detect the blob format from its prefix."""
    if data[:5] == _EYED1_PREFIX:
        return "aes"
    if data[:4] == _HEV1_PREFIX:
        return "he"
    if data[:4] == _NPZ_MAGIC:
        return "npz"
    return "unknown"


async def migrate(db_url: str, key: bytes, dry_run: bool) -> dict:
    """Run the migration.

    Returns a dict with counts: {total, aes, he, npz, unknown, migrated, errors}.
    """
    conn = await asyncpg.connect(db_url)
    try:
        rows = await conn.fetch(
            "SELECT template_id, iris_codes, mask_codes FROM templates"
        )
    except Exception:
        logger.exception("Failed to query templates")
        await conn.close()
        raise

    stats = {
        "total": len(rows),
        "aes": 0,
        "he": 0,
        "npz": 0,
        "unknown": 0,
        "migrated": 0,
        "errors": 0,
    }

    logger.info("Found %d templates to check", len(rows))

    for row in rows:
        tid = row["template_id"]
        iris_raw = bytes(row["iris_codes"])
        mask_raw = bytes(row["mask_codes"])

        iris_fmt = detect_format(iris_raw)
        mask_fmt = detect_format(mask_raw)

        if iris_fmt != "aes" and mask_fmt != "aes":
            stats[iris_fmt] = stats.get(iris_fmt, 0) + 1
            continue

        stats["aes"] += 1

        if dry_run:
            logger.info("[DRY RUN] Template %s: would decrypt AES → NPZ", tid)
            continue

        try:
            new_iris = decrypt_aes(iris_raw, key) if iris_fmt == "aes" else iris_raw
            new_mask = decrypt_aes(mask_raw, key) if mask_fmt == "aes" else mask_raw

            await conn.execute(
                "UPDATE templates SET iris_codes = $1, mask_codes = $2 "
                "WHERE template_id = $3",
                new_iris,
                new_mask,
                tid,
            )
            stats["migrated"] += 1
            logger.info("Migrated template %s: AES → NPZ", tid)
        except Exception:
            stats["errors"] += 1
            logger.exception("Failed to migrate template %s", tid)

    await conn.close()
    return stats


def main():
    parser = argparse.ArgumentParser(
        description="Migrate AES-encrypted templates to plain NPZ format."
    )
    parser.add_argument(
        "--db-url",
        required=True,
        help="PostgreSQL connection URL",
    )
    parser.add_argument(
        "--encryption-key",
        required=True,
        help="AES-256 key (64 hex chars or 44 base64 chars)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Count affected rows without modifying the database",
    )
    args = parser.parse_args()

    try:
        key = parse_key(args.encryption_key)
    except ValueError as e:
        logger.error("Invalid encryption key: %s", e)
        sys.exit(1)

    stats = asyncio.run(migrate(args.db_url, key, args.dry_run))

    logger.info("--- Migration Summary ---")
    logger.info("Total templates:  %d", stats["total"])
    logger.info("AES-encrypted:    %d", stats["aes"])
    logger.info("HE ciphertexts:   %d", stats["he"])
    logger.info("Plain NPZ:        %d", stats["npz"])
    logger.info("Unknown format:   %d", stats["unknown"])
    if not args.dry_run:
        logger.info("Migrated:         %d", stats["migrated"])
        logger.info("Errors:           %d", stats["errors"])
    else:
        logger.info("(Dry run — no changes made)")

    if stats["errors"] > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
