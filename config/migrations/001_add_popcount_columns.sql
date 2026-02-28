-- Migration: Add popcount columns for HE Hamming distance computation
-- Run this on existing databases before enabling HE mode.
-- These columns are NULL for non-HE templates and populated for HE templates.

ALTER TABLE templates ADD COLUMN IF NOT EXISTS iris_popcount INT[];
ALTER TABLE templates ADD COLUMN IF NOT EXISTS mask_popcount INT[];
