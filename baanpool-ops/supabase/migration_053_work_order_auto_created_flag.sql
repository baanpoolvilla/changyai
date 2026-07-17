-- =====================================================
-- BaanPool Ops — Migration 053
-- ติดธงว่าใบงานถูกสร้างอัตโนมัติจาก PM (ไว้โชว์แท็กในแอป)
--
-- ต้องรัน migration 052 ก่อน
-- Run this SQL in Supabase SQL Editor (Dashboard > SQL)
-- =====================================================

ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS auto_created BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.work_orders.auto_created IS
  'true = ใบงานนี้ระบบสร้างอัตโนมัติจาก PM ที่ถึงกำหนด (ไม่ใช่คนกดสร้าง)';

-- อัปเดตฟังก์ชันให้ติดธง auto_created = true
CREATE OR REPLACE FUNCTION public.auto_create_pm_work_orders()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pm         RECORD;
  v_count      INT := 0;
  v_assignee   UUID;
  v_asset_name TEXT;
  v_desc       TEXT;
BEGIN
  FOR v_pm IN
    SELECT ps.id, ps.title, ps.description, ps.property_id, ps.asset_id,
           ps.assigned_to, ps.next_due_date, ps.frequency,
           p.caretaker_id, p.name AS property_name
    FROM public.pm_schedules ps
    JOIN public.properties p ON p.id = ps.property_id
    WHERE ps.is_active = true
      AND ps.next_due_date <= CURRENT_DATE
      AND NOT EXISTS (
        SELECT 1 FROM public.work_orders wo
        WHERE wo.pm_schedule_id = ps.id
          AND wo.status NOT IN ('completed', 'cancelled')
      )
  LOOP
    -- มอบหมายตาม PM ก่อน ถ้าไม่มี → ผู้ดูแลบ้าน
    v_assignee := COALESCE(v_pm.assigned_to, v_pm.caretaker_id);

    v_asset_name := NULL;
    IF v_pm.asset_id IS NOT NULL THEN
      SELECT name INTO v_asset_name FROM public.assets WHERE id = v_pm.asset_id;
    END IF;

    v_desc := 'PM: ' || v_pm.title
           || E'\nบ้าน: '   || v_pm.property_name
           || COALESCE(E'\nอุปกรณ์: ' || v_asset_name, '')
           || E'\nกำหนด: '  || to_char(v_pm.next_due_date, 'DD/MM/YYYY')
           || COALESCE(E'\nรายละเอียด: ' || v_pm.description, '')
           || E'\n\n(ใบงานนี้ระบบสร้างอัตโนมัติจาก PM)';

    INSERT INTO public.work_orders (
      property_id, asset_id, assigned_to, title, description,
      status, priority, due_date, pm_schedule_id, auto_created
    ) VALUES (
      v_pm.property_id, v_pm.asset_id, v_assignee, v_pm.title, v_desc,
      'open', 'medium', v_pm.next_due_date::timestamptz, v_pm.id, true
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ใบงานที่ migration 052 สร้างไปแล้ว (ถ้ามี) → ติดธงย้อนหลังจากข้อความใน description
UPDATE public.work_orders
SET auto_created = true
WHERE pm_schedule_id IS NOT NULL
  AND auto_created = false
  AND description LIKE '%(ใบงานนี้ระบบสร้างอัตโนมัติจาก PM)%';
