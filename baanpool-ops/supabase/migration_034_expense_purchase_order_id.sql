-- =====================================================
-- BaanPool Ops — Migration 034
-- เพิ่ม purchase_order_id ใน expenses
-- เพื่อให้สามารถ navigate กลับไปยัง PO ได้
-- =====================================================

ALTER TABLE public.expenses
  ADD COLUMN IF NOT EXISTS purchase_order_id UUID
    REFERENCES public.purchase_orders(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_expenses_po_id
  ON public.expenses(purchase_order_id);
