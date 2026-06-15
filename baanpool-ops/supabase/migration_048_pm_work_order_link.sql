-- Link work orders to the PM schedule that created them
ALTER TABLE work_orders
  ADD COLUMN IF NOT EXISTS pm_schedule_id UUID REFERENCES pm_schedules(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_work_orders_pm_schedule_id ON work_orders(pm_schedule_id);
