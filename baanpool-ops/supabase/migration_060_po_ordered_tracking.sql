-- migration_060_po_ordered_tracking.sql
-- เพิ่มการเก็บ "ผู้ดำเนินการซื้อ + เวลา" ของเฟส ordered (กำลังดำเนินการ/ไปซื้อของ)
-- เพื่อให้ timeline ในหน้ารายละเอียดแสดงครบทุกเฟส:
--   เปิด PR → สร้าง PO → ดำเนินการซื้อ → รับของ

ALTER TABLE public.purchase_orders
  ADD COLUMN IF NOT EXISTS ordered_by UUID REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS ordered_at TIMESTAMPTZ;

-- Backfill เวลาคร่าว ๆ ให้รายการที่ผ่านเฟสนี้ไปแล้ว (ยังไม่รู้ "ใคร" จึงเว้น by)
UPDATE public.purchase_orders
SET ordered_at = updated_at
WHERE status IN ('ordered', 'received')
  AND ordered_at IS NULL
  AND is_emergency_purchase = FALSE;

SELECT 'migration_060 OK' AS result;
