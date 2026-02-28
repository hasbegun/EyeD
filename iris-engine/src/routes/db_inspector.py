"""Admin DB Inspector — browse tables, schemas, and encrypted template metadata."""

from __future__ import annotations

import struct
from typing import Optional

from fastapi import APIRouter, HTTPException, Query

from ..db import get_pool
from ..models import (
    ByteaInfo,
    ColumnInfo,
    DbSchemaResponse,
    DbStatsResponse,
    ForeignKeyInfo,
    RowDetailResponse,
    TableRowsResponse,
    TableSchema,
)

router = APIRouter(prefix="/admin/db", tags=["admin-db"])

# Only these tables can be queried — prevents SQL injection.
_ALLOWED_TABLES = {"identities", "templates", "match_log"}

# Primary key column for each table.
_PK_COLUMNS = {
    "identities": "identity_id",
    "templates": "template_id",
    "match_log": "log_id",
}

# Default ordering for each table.
_ORDER_COLUMNS = {
    "identities": "created_at DESC",
    "templates": "enrolled_at DESC",
    "match_log": "log_id DESC",
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _describe_bytea(data: bytes) -> ByteaInfo:
    """Extract metadata from a BYTEA value without transferring the full blob."""
    prefix_hex = data[:32].hex()
    fmt = "unknown"
    he_count = None
    he_sizes = None

    if len(data) >= 4 and data[:4] == b"PK\x03\x04":
        fmt = "npz"
    elif len(data) >= 8 and data[:4] == b"HEv1":
        fmt = "hev1"
        he_count = struct.unpack("<I", data[4:8])[0]
        he_sizes = []
        offset = 8
        for _ in range(he_count):
            if offset + 4 <= len(data):
                ct_len = struct.unpack("<I", data[offset : offset + 4])[0]
                he_sizes.append(ct_len)
                offset += 4 + ct_len

    return ByteaInfo(
        size_bytes=len(data),
        prefix_hex=prefix_hex,
        format=fmt,
        he_ciphertext_count=he_count,
        he_per_ct_sizes=he_sizes,
    )


def _serialize_row(row: dict) -> dict:
    """Convert asyncpg Record values to JSON-safe types."""
    out = {}
    for key, value in row.items():
        if value is None:
            out[key] = None
        elif isinstance(value, (bytes, bytearray, memoryview)):
            out[key] = _describe_bytea(bytes(value)).dict()
        elif hasattr(value, "isoformat"):
            out[key] = value.isoformat()
        elif hasattr(value, "hex") and not isinstance(value, (str, int, float)):
            # UUID
            out[key] = str(value)
        else:
            out[key] = value
    return out


def _validate_table(table_name: str) -> None:
    if table_name not in _ALLOWED_TABLES:
        raise HTTPException(
            status_code=400,
            detail=f"Table '{table_name}' not allowed. "
            f"Allowed: {sorted(_ALLOWED_TABLES)}",
        )


def _require_pool():
    pool = get_pool()
    if pool is None:
        raise HTTPException(status_code=503, detail="Database not connected")
    return pool


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get("/schema", response_model=DbSchemaResponse)
async def get_schema():
    """Return schema metadata for all known tables."""
    pool = _require_pool()
    tables_list = sorted(_ALLOWED_TABLES)

    async with pool.acquire() as conn:
        # Column metadata
        col_rows = await conn.fetch(
            """
            SELECT table_name, column_name, udt_name, is_nullable, column_default
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = ANY($1)
            ORDER BY table_name, ordinal_position
            """,
            tables_list,
        )

        # Primary keys
        pk_rows = await conn.fetch(
            """
            SELECT tc.table_name, kcu.column_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON tc.constraint_name = kcu.constraint_name
              AND tc.table_schema = kcu.table_schema
            WHERE tc.table_schema = 'public'
              AND tc.constraint_type = 'PRIMARY KEY'
              AND tc.table_name = ANY($1)
            """,
            tables_list,
        )

        # Foreign keys
        fk_rows = await conn.fetch(
            """
            SELECT tc.table_name, kcu.column_name,
                   ccu.table_name AS referenced_table,
                   ccu.column_name AS referenced_column
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON tc.constraint_name = kcu.constraint_name
              AND tc.table_schema = kcu.table_schema
            JOIN information_schema.constraint_column_usage ccu
              ON tc.constraint_name = ccu.constraint_name
              AND tc.table_schema = ccu.table_schema
            WHERE tc.table_schema = 'public'
              AND tc.constraint_type = 'FOREIGN KEY'
              AND tc.table_name = ANY($1)
            """,
            tables_list,
        )

        # Approximate row counts
        count_rows = await conn.fetch(
            """
            SELECT relname, n_live_tup::int AS row_count
            FROM pg_stat_user_tables
            WHERE relname = ANY($1)
            """,
            tables_list,
        )

    # Build lookup structures
    pk_set = {(r["table_name"], r["column_name"]) for r in pk_rows}
    counts = {r["relname"]: r["row_count"] for r in count_rows}

    fk_by_table: dict[str, list] = {t: [] for t in tables_list}
    for r in fk_rows:
        fk_by_table[r["table_name"]].append(
            ForeignKeyInfo(
                column=r["column_name"],
                referenced_table=r["referenced_table"],
                referenced_column=r["referenced_column"],
            )
        )

    cols_by_table: dict[str, list] = {t: [] for t in tables_list}
    for r in col_rows:
        tname = r["table_name"]
        cols_by_table[tname].append(
            ColumnInfo(
                name=r["column_name"],
                data_type=r["udt_name"],
                nullable=r["is_nullable"] == "YES",
                default_value=r["column_default"],
                is_primary_key=(tname, r["column_name"]) in pk_set,
            )
        )

    tables = [
        TableSchema(
            table_name=t,
            columns=cols_by_table.get(t, []),
            foreign_keys=fk_by_table.get(t, []),
            row_count=counts.get(t, 0),
        )
        for t in tables_list
    ]

    return DbSchemaResponse(tables=tables)


@router.get("/stats", response_model=DbStatsResponse)
async def get_stats():
    """Quick aggregate counts for the overview."""
    pool = _require_pool()

    async with pool.acquire() as conn:
        id_count = await conn.fetchval("SELECT COUNT(*) FROM identities")
        tpl_count = await conn.fetchval("SELECT COUNT(*) FROM templates")
        log_count = await conn.fetchval(
            "SELECT n_live_tup::int FROM pg_stat_user_tables WHERE relname = 'match_log'"
        )
        he_count = await conn.fetchval(
            "SELECT COUNT(*) FROM templates WHERE substring(iris_codes FROM 1 FOR 4) = $1",
            b"HEv1",
        )
        npz_count = await conn.fetchval(
            "SELECT COUNT(*) FROM templates WHERE substring(iris_codes FROM 1 FOR 4) = $1",
            b"PK\x03\x04",
        )
        db_size = await conn.fetchval(
            "SELECT pg_database_size(current_database())"
        )

    return DbStatsResponse(
        identities_count=id_count or 0,
        templates_count=tpl_count or 0,
        match_log_count=log_count or 0,
        he_templates_count=he_count or 0,
        npz_templates_count=npz_count or 0,
        db_size_bytes=db_size or 0,
    )


@router.get("/tables/{table_name}/rows", response_model=TableRowsResponse)
async def get_table_rows(
    table_name: str,
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
):
    """Paginated row listing for a table. BYTEA columns become metadata objects."""
    _validate_table(table_name)
    pool = _require_pool()

    order = _ORDER_COLUMNS[table_name]

    async with pool.acquire() as conn:
        # Safe: table_name is from the allowlist
        rows = await conn.fetch(
            f"SELECT * FROM {table_name} ORDER BY {order} LIMIT $1 OFFSET $2",
            limit,
            offset,
        )
        total = await conn.fetchval(f"SELECT COUNT(*) FROM {table_name}")

    columns = [k for k in rows[0].keys()] if rows else []
    serialized = [_serialize_row(dict(r)) for r in rows]

    return TableRowsResponse(
        table_name=table_name,
        columns=columns,
        rows=serialized,
        total_count=total or 0,
        has_more=(offset + limit) < (total or 0),
    )


@router.get("/tables/{table_name}/rows/{row_id}", response_model=RowDetailResponse)
async def get_row_detail(table_name: str, row_id: str):
    """Single row detail with related data from FK tables."""
    _validate_table(table_name)
    pool = _require_pool()

    pk_col = _PK_COLUMNS[table_name]

    async with pool.acquire() as conn:
        # Cast row_id to the appropriate type
        if table_name == "match_log":
            row = await conn.fetchrow(
                f"SELECT * FROM {table_name} WHERE {pk_col} = $1",
                int(row_id),
            )
        else:
            import uuid as _uuid

            row = await conn.fetchrow(
                f"SELECT * FROM {table_name} WHERE {pk_col} = $1",
                _uuid.UUID(row_id),
            )

        if row is None:
            raise HTTPException(status_code=404, detail="Row not found")

        serialized = _serialize_row(dict(row))
        related: Optional[dict] = None

        # Fetch related data
        if table_name == "templates":
            identity = await conn.fetchrow(
                "SELECT identity_id, name, created_at FROM identities WHERE identity_id = $1",
                row["identity_id"],
            )
            if identity:
                related = {"identity": _serialize_row(dict(identity))}

        elif table_name == "match_log":
            rel = {}
            if row["matched_identity_id"]:
                identity = await conn.fetchrow(
                    "SELECT identity_id, name FROM identities WHERE identity_id = $1",
                    row["matched_identity_id"],
                )
                if identity:
                    rel["matched_identity"] = _serialize_row(dict(identity))
            if row["matched_template_id"]:
                tpl = await conn.fetchrow(
                    "SELECT template_id, identity_id, eye_side, width, height, enrolled_at "
                    "FROM templates WHERE template_id = $1",
                    row["matched_template_id"],
                )
                if tpl:
                    rel["matched_template"] = _serialize_row(dict(tpl))
            if rel:
                related = rel

    return RowDetailResponse(
        table_name=table_name,
        primary_key=row_id,
        row=serialized,
        related=related,
    )
