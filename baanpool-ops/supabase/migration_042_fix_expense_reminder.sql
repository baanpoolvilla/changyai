-- =====================================================
-- BaanPool Ops — Migration 042
-- แก้ expense reminder:
-- - ปิด cron เดิม (ไม่มี dedup ส่งซ้ำทุกวัน)
-- - ไม่เปิด cron ใหม่ (ให้ใช้ in-app notification แทน)
-- =====================================================

-- 1. ปิด cron job เดิมที่ส่ง LINE ซ้ำทุกวัน
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'notify-missing-expenses') THEN
    PERFORM cron.unschedule('notify-missing-expenses');
    RAISE NOTICE 'Unscheduled notify-missing-expenses';
  ELSE
    RAISE NOTICE 'Job not found - already removed';
  END IF;
END $$;

-- 2. แทนด้วย function ใหม่ที่สร้างแค่ in-app notification (ไม่ส่ง LINE)
--    เพราะ completed work orders ไม่มี expense อาจมีหลายร้อยรายการ
--    ถ้าส่ง LINE ทุกรายการทุกวัน = quota หมดใน 1 วัน
CREATE OR REPLACE FUNCTION public.notify_missing_expenses()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_wo        RECORD;
  v_count     INT := 0;
  v_today     TIMESTAMPTZ := date_trunc('day', NOW() AT TIME ZONE 'UTC');
BEGIN
  -- วน work orders ที่ completed แต่ยังไม่มี expense
  -- สร้าง in-app notification ให้ caretaker เท่านั้น (dedup รายวัน)
  FOR v_wo IN
    SELECT
      wo.id,
      wo.title,
      wo.property_id,
      p.name        AS property_name,
      p.caretaker_id
    FROM public.work_orders wo
    JOIN public.properties p ON p.id = wo.property_id
    WHERE wo.status = 'completed'
      AND p.caretaker_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.expenses e
        WHERE e.work_order_id = wo.id
      )
      -- ไม่สร้างซ้ำถ้าแจ้งไปแล้ววันนี้
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.user_id      = p.caretaker_id
          AND n.reference_id = wo.id::TEXT
          AND n.type         = 'expense_reminder'
          AND n.created_at  >= v_today
      )
  LOOP
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_wo.caretaker_id,
      '⚠️ ยังไม่บันทึกค่าใช้จ่าย',
      '📝 ' || v_wo.title || chr(10) || '🏠 ' || COALESCE(v_wo.property_name, '-'),
      'expense_reminder',
      v_wo.id::TEXT
    )
    ON CONFLICT DO NOTHING;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ตรวจสอบผล
SELECT 'migration_042 OK — expense LINE cron disabled' AS result;
SELECT jobname, active FROM cron.job ORDER BY jobname;
