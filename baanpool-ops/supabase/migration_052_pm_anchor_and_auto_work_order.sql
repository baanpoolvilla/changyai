-- =====================================================
-- BaanPool Ops — Migration 052
-- 1) PM ยึดวันตั้งต้น (anchor) + รอบต่อปี → วันกำหนดไม่ดริฟต์
-- 2) สร้างใบงานอัตโนมัติเมื่อ PM ถึงกำหนด
--
-- โมเดล: รอบที่ i ของปี = anchor_date + (i × ระยะห่าง) เดือน
--        วนกลับ anchor ทุก 12 เดือน
--   เช่น ล้างแอร์ anchor 15/9/2026, ทุก 3 เดือน, 3 รอบ/ปี
--        → 15/9/2026, 15/12/2026, 15/3/2027, [เว้น มิ.ย.], 15/9/2027, ...
--
-- Run this SQL in Supabase SQL Editor (Dashboard > SQL)
-- =====================================================

-- ─── 1. คอลัมน์ใหม่ ────────────────────────────────
ALTER TABLE public.pm_schedules
  ADD COLUMN IF NOT EXISTS anchor_date DATE,
  ADD COLUMN IF NOT EXISTS rounds_per_year INT;

COMMENT ON COLUMN public.pm_schedules.anchor_date IS
  'วันตั้งต้นของรอบ PM — ใช้คำนวณวันกำหนดถัดไป ไม่ให้ดริฟต์ตามวันจบงาน';
COMMENT ON COLUMN public.pm_schedules.rounds_per_year IS
  'จำนวนรอบต่อปี (นับจาก anchor) — NULL = ทำต่อเนื่องทุกช่วง ไม่มีการเว้น';

-- rounds_per_year ต้องอยู่ในช่วง 1-12
ALTER TABLE public.pm_schedules
  DROP CONSTRAINT IF EXISTS pm_schedules_rounds_per_year_check;
ALTER TABLE public.pm_schedules
  ADD CONSTRAINT pm_schedules_rounds_per_year_check
  CHECK (rounds_per_year IS NULL OR (rounds_per_year BETWEEN 1 AND 12));

-- ─── 2. Backfill ของเดิม ───────────────────────────
-- anchor = วันกำหนดปัจจุบัน (ตั้งแต่นี้ไปจะยึดวันนี้เป็นหลัก ไม่ดริฟต์อีก)
UPDATE public.pm_schedules
SET anchor_date = next_due_date
WHERE anchor_date IS NULL;

-- rounds_per_year = NULL สำหรับของเดิม → ทำต่อเนื่องเหมือนพฤติกรรมเดิม
-- (PM ที่สร้างใหม่จะบังคับให้เลือกรอบต่อปีเอง)

-- ─── 3. สร้างใบงานอัตโนมัติเมื่อ PM ถึงกำหนด ─────────
-- มอบหมาย: ตาม PM ก่อน ถ้าไม่ระบุ → ผู้ดูแลบ้าน (caretaker)
-- ข้าม PM ที่ยังมีใบงานค้างอยู่ (กันสร้างซ้ำทุกวัน)
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
      status, priority, due_date, pm_schedule_id
    ) VALUES (
      v_pm.property_id, v_pm.asset_id, v_assignee, v_pm.title, v_desc,
      'open', 'medium', v_pm.next_due_date::timestamptz, v_pm.id
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ─── 4. cron ───────────────────────────────────────
-- ปิด PM digest เดิม (ซ้ำกับแจ้งเตือน "งานใหม่" ที่ trg_work_order_assigned ยิงอยู่แล้ว)
SELECT cron.unschedule('pm_due_daily_check')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'pm_due_daily_check');

SELECT cron.unschedule('pm_auto_create_work_orders')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'pm_auto_create_work_orders');

-- ทุกวัน 01:00 UTC = 08:00 น. ไทย
SELECT cron.schedule(
  'pm_auto_create_work_orders',
  '0 1 * * *',
  $$ SELECT public.auto_create_pm_work_orders(); $$
);
