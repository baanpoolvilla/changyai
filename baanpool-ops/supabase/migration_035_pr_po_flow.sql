-- migration_035_pr_po_flow.sql
-- เพิ่ม field สำหรับระบบ PR→PO flow ใหม่
-- po_assigned_to: CEO เลือกคนที่จะไปซื้อของ (รับ PO)
-- is_emergency_purchase: กรณีฉุกเฉิน ซื้อของก่อนแล้วแจ้ง CEO ทีหลัง
-- emergency_reason: เหตุผลกรณีฉุกเฉิน

ALTER TABLE purchase_orders
  ADD COLUMN IF NOT EXISTS po_assigned_to UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS is_emergency_purchase BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS emergency_reason TEXT;
