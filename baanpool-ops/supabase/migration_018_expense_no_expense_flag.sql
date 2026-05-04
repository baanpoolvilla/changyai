-- =====================================================
-- BaanPool Ops — Migration 018: Mark no-expense records explicitly
-- เพิ่ม flag เพื่อบันทึกว่าใบงาน/PM ไม่มีค่าใช้จ่าย
-- =====================================================

ALTER TABLE public.expenses
  ADD COLUMN IF NOT EXISTS is_no_expense BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_expenses_is_no_expense
  ON public.expenses(is_no_expense);