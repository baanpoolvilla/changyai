-- =====================================================
-- BaanPool Ops — Add Zone to Contractors
-- =====================================================
-- Adds a zone/area field to contractors table
-- Zones: บางแสน, พัทยา, ทั่วไป, etc.
-- =====================================================

ALTER TABLE public.contractors
  ADD COLUMN IF NOT EXISTS zone TEXT;

COMMENT ON COLUMN public.contractors.zone IS 'พื้นที่รับผิดชอบของ contact เช่น บางแสน, พัทยา, ทั่วไป';
