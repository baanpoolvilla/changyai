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

-- 2. แทนด้วย function ใหม่แบบ digest
--    รวมทุก work order ที่ค้างต่อ caretaker → ส่ง LINE 1 ข้อความ/คน/วัน
--    + สร้าง in-app notification รายรายการ (dedup รายวัน)
CREATE OR REPLACE FUNCTION public.notify_missing_expenses()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caretaker   RECORD;
  v_wo          RECORD;
  v_count       INT := 0;
  v_wo_count    INT;
  v_wo_lines    TEXT;
  v_message     TEXT;
  v_digest_key  TEXT;
  v_today       TIMESTAMPTZ := date_trunc('day', NOW() AT TIME ZONE 'UTC');
  v_today_str   TEXT        := to_char(CURRENT_DATE, 'DD/MM/YYYY');
BEGIN
  -- วนต่อ caretaker ที่มี work order ค้าง
  FOR v_caretaker IN
    SELECT DISTINCT p.caretaker_id, u.line_user_id, u.full_name
    FROM public.work_orders wo
    JOIN public.properties  p ON p.id = wo.property_id
    JOIN public.users       u ON u.id = p.caretaker_id
    WHERE wo.status = 'completed'
      AND p.caretaker_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.expenses e WHERE e.work_order_id = wo.id)
  LOOP
    -- dedup digest LINE รายวัน
    v_digest_key := 'exp_digest_' || v_caretaker.caretaker_id::TEXT || '_' || to_char(CURRENT_DATE, 'YYYYMMDD');
    IF EXISTS (
      SELECT 1 FROM public.notifications
      WHERE user_id = v_caretaker.caretaker_id
        AND reference_id = v_digest_key
        AND type = 'expense_digest'
        AND created_at >= v_today
    ) THEN CONTINUE; END IF;

    -- รวมรายการค้าง
    v_wo_lines := '';
    v_wo_count := 0;

    FOR v_wo IN
      SELECT wo.id, wo.title, p.name AS property_name
      FROM public.work_orders wo
      JOIN public.properties  p ON p.id = wo.property_id
      WHERE wo.status = 'completed'
        AND p.caretaker_id = v_caretaker.caretaker_id
        AND NOT EXISTS (SELECT 1 FROM public.expenses e WHERE e.work_order_id = wo.id)
      ORDER BY wo.updated_at DESC
      LIMIT 20
    LOOP
      v_wo_count := v_wo_count + 1;
      v_wo_lines := v_wo_lines
        || '  ' || v_wo_count || '. ' || v_wo.title
        || ' (' || v_wo.property_name || ')' || chr(10);

      -- in-app notification รายรายการ (dedup รายวัน)
      IF NOT EXISTS (
        SELECT 1 FROM public.notifications
        WHERE user_id = v_caretaker.caretaker_id
          AND reference_id = v_wo.id::TEXT
          AND type = 'expense_reminder'
          AND created_at >= v_today
      ) THEN
        INSERT INTO public.notifications (user_id, title, body, type, reference_id)
        VALUES (
          v_caretaker.caretaker_id,
          '⚠️ ยังไม่บันทึกค่าใช้จ่าย: ' || v_wo.title,
          '🏠 ' || v_wo.property_name,
          'expense_reminder',
          v_wo.id::TEXT
        ) ON CONFLICT DO NOTHING;
      END IF;
    END LOOP;

    IF v_wo_count = 0 THEN CONTINUE; END IF;

    -- บันทึก digest sentinel
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_caretaker.caretaker_id,
      '⚠️ ค่าใช้จ่ายค้างบันทึก ' || v_wo_count || ' รายการ',
      v_wo_lines,
      'expense_digest',
      v_digest_key
    ) ON CONFLICT DO NOTHING;

    -- ส่ง LINE digest 1 ข้อความต่อ caretaker ต่อวัน
    IF v_caretaker.line_user_id IS NOT NULL AND v_caretaker.line_user_id != '' THEN
      v_message :=
        '⚠️ ค่าใช้จ่ายค้างบันทึก — ' || v_today_str || chr(10)
        || '📋 มี ' || v_wo_count || ' ใบงานที่ยังไม่กรอกค่าใช้จ่าย:' || chr(10)
        || v_wo_lines
        || '🔗 https://changyai.vercel.app/work-orders';
      PERFORM public.send_line_text(v_caretaker.line_user_id, v_message);
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- 3. ตั้ง cron ใหม่ส่งตอน 17:00 Bangkok (10:00 UTC) — digest 1 ข้อความ/คน
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'notify-missing-expenses') THEN
    PERFORM cron.unschedule('notify-missing-expenses');
  END IF;
END $$;

SELECT cron.schedule(
  'notify-missing-expenses',
  '0 10 * * *',
  $$ SELECT public.notify_missing_expenses(); $$
);

-- ตรวจสอบผล
SELECT 'migration_042 OK — expense LINE cron disabled' AS result;
SELECT jobname, active FROM cron.job ORDER BY jobname;
