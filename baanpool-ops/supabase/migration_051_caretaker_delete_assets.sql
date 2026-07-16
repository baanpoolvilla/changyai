-- =====================================================
-- BaanPool Ops — Migration 051
-- Allow caretakers to DELETE assets for their own properties.
--
-- ปัญหา: ผู้ดูแลบ้าน (caretaker) สร้าง/แก้ไขอุปกรณ์ได้ (migration 039)
--         แต่ "ลบไม่ได้" เพราะไม่มี RLS DELETE policy สำหรับ caretaker
--         → PostgREST ลบ 0 แถวโดยไม่ error แอปเลยขึ้น "สำเร็จ" แต่ของไม่หาย
--
-- Run this SQL in Supabase SQL Editor (Dashboard > SQL)
-- =====================================================

-- Caretaker can delete assets for their assigned properties.
DROP POLICY IF EXISTS "Caretaker can delete assets for own properties" ON public.assets;
CREATE POLICY "Caretaker can delete assets for own properties"
  ON public.assets FOR DELETE
  TO authenticated
  USING (
    public.get_user_role() = 'caretaker'
    AND property_id IN (
      SELECT id FROM public.properties WHERE caretaker_id = auth.uid()
    )
  );

-- หมายเหตุ: pm_schedules.asset_id เป็น FK ON DELETE SET NULL
-- ดังนั้นเมื่อลบอุปกรณ์ PM Schedule ที่ผูกไว้จะถูกตั้ง asset_id = NULL
-- (referential action ทำงานในสิทธิ์ owner จึงไม่ติด RLS)
