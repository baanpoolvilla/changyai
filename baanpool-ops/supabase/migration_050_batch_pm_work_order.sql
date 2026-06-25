-- Migration 050: Add pm_schedule_ids array for batch PM work orders
-- Allows one work order to link to multiple PM schedules of the same type across multiple houses

ALTER TABLE work_orders
ADD COLUMN IF NOT EXISTS pm_schedule_ids TEXT[] DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_work_orders_pm_schedule_ids
ON work_orders USING GIN(pm_schedule_ids);
