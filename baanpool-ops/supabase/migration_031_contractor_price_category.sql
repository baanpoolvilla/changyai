-- Migration 031: Add price and category columns to contractors table
ALTER TABLE contractors
  ADD COLUMN IF NOT EXISTS price NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS category TEXT;

-- Optional: Add an index on category for faster filtering
CREATE INDEX IF NOT EXISTS idx_contractors_category ON contractors (category);
