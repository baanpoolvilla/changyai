-- migration_058_po_state_tracking.sql
-- แยกผู้ทำ + วันที่ ของแต่ละสเต็ปใน PR/PO flow
--   * created_by / created_at  = เปิด PR (มีอยู่แล้ว)
--   * po_created_by / po_created_at = คนสร้าง/อนุมัติ PO และเวลาที่สร้าง PO
--   * received_by / received_at     = คนที่รับของ และเวลาที่รับของ

ALTER TABLE public.purchase_orders
  ADD COLUMN IF NOT EXISTS po_created_by UUID REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS po_created_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS received_by   UUID REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS received_at   TIMESTAMPTZ;

-- Backfill เวลาคร่าว ๆ จากข้อมูลเดิม (ยังไม่รู้ "ใคร" จึงเว้น by ไว้ null)
UPDATE public.purchase_orders
SET received_at = updated_at
WHERE status = 'received' AND received_at IS NULL;

SELECT 'migration_058 OK' AS result;
