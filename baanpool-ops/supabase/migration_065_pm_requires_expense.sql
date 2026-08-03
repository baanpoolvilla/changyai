-- =====================================================
-- BaanPool Ops — Migration 065
-- PM ระบุได้ว่า "จบงานแล้วมีค่าใช้จ่ายไหม"
--
-- ตอนสร้าง PM เลือกได้ว่า มีค่าใช้จ่าย / ไม่มีค่าใช้จ่าย
-- ใบงานที่สร้างจาก PM นั้น (ทั้งแบบอัตโนมัติและกดสร้างเอง)
-- จะรับค่านี้ไปด้วย → ใบงานที่ "ไม่มีค่าใช้จ่าย" พอปิดงานแล้ว
-- ถือว่าเสร็จสมบูรณ์ทันที ไม่ต้องรอบันทึกค่าใช้จ่าย
-- และไม่ถูกทวงในแจ้งเตือนค่าใช้จ่ายค้างบันทึก
--
-- ต้องรัน migration 052-056 ก่อน
-- Run this SQL in Supabase SQL Editor (Dashboard > SQL)
-- =====================================================

-- ─── 1. คอลัมน์ใหม่ ────────────────────────────────
-- default true = พฤติกรรมเดิม (ทุกใบงานต้องบันทึกค่าใช้จ่าย)
ALTER TABLE public.pm_schedules
  ADD COLUMN IF NOT EXISTS requires_expense BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS requires_expense BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN public.pm_schedules.requires_expense IS
  'true = จบงานแล้วต้องบันทึกค่าใช้จ่าย, false = งานนี้ไม่มีค่าใช้จ่าย';
COMMENT ON COLUMN public.work_orders.requires_expense IS
  'true = ต้องบันทึกค่าใช้จ่ายหลังปิดงาน, false = ไม่มีค่าใช้จ่าย (รับค่ามาจาก PM)';

-- ─── 2. ใบงานที่ผูกกับ PM รับค่าจาก PM ─────────────
-- ครอบคลุมทั้ง 3 ทาง: auto_create_pm_work_orders(), กดสร้างใบงานจากการ์ด PM,
-- และใบงานรวมหลายบ้าน (pm_schedule_ids)
CREATE OR REPLACE FUNCTION public.set_work_order_requires_expense()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_flag BOOLEAN;
BEGIN
  IF NEW.pm_schedule_id IS NOT NULL THEN
    SELECT ps.requires_expense INTO v_flag
    FROM public.pm_schedules ps
    WHERE ps.id = NEW.pm_schedule_id;
  ELSIF NEW.pm_schedule_ids IS NOT NULL
        AND array_length(NEW.pm_schedule_ids, 1) > 0 THEN
    -- ใบงานรวมหลาย PM — มี PM ใดใบหนึ่งที่มีค่าใช้จ่าย ก็ต้องบันทึก
    -- pm_schedule_ids เป็น TEXT[] (migration_050) ต้อง cast id ก่อนเทียบ
    SELECT bool_or(ps.requires_expense) INTO v_flag
    FROM public.pm_schedules ps
    WHERE ps.id::TEXT = ANY(NEW.pm_schedule_ids);
  END IF;

  IF v_flag IS NOT NULL THEN
    NEW.requires_expense := v_flag;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_order_requires_expense ON public.work_orders;
CREATE TRIGGER trg_work_order_requires_expense
  BEFORE INSERT ON public.work_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.set_work_order_requires_expense();

-- ─── 3. ไม่ทวงค่าใช้จ่ายกับใบงานที่ไม่มีค่าใช้จ่าย ───
-- เหมือน migration_042 ทุกอย่าง เพิ่มแค่เงื่อนไข requires_expense
DROP FUNCTION IF EXISTS public.notify_missing_expenses();
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
  FOR v_caretaker IN
    SELECT DISTINCT p.caretaker_id, u.line_user_id, u.full_name
    FROM public.work_orders wo
    JOIN public.properties  p ON p.id = wo.property_id
    JOIN public.users       u ON u.id = p.caretaker_id
    WHERE wo.status = 'completed'
      AND wo.requires_expense = true
      AND p.caretaker_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.expenses e WHERE e.work_order_id = wo.id)
  LOOP
    v_digest_key := 'exp_digest_' || v_caretaker.caretaker_id::TEXT || '_' || to_char(CURRENT_DATE, 'YYYYMMDD');
    IF EXISTS (
      SELECT 1 FROM public.notifications
      WHERE user_id = v_caretaker.caretaker_id
        AND reference_id = v_digest_key
        AND type = 'expense_digest'
        AND created_at >= v_today
    ) THEN CONTINUE; END IF;

    v_wo_lines := '';
    v_wo_count := 0;

    FOR v_wo IN
      SELECT wo.id, wo.title, p.name AS property_name
      FROM public.work_orders wo
      JOIN public.properties  p ON p.id = wo.property_id
      WHERE wo.status = 'completed'
        AND wo.requires_expense = true
        AND p.caretaker_id = v_caretaker.caretaker_id
        AND NOT EXISTS (SELECT 1 FROM public.expenses e WHERE e.work_order_id = wo.id)
      ORDER BY wo.updated_at DESC
      LIMIT 20
    LOOP
      v_wo_count := v_wo_count + 1;
      v_wo_lines := v_wo_lines
        || '  ' || v_wo_count || '. ' || v_wo.title
        || ' (' || v_wo.property_name || ')' || chr(10);

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

    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_caretaker.caretaker_id,
      '⚠️ ค่าใช้จ่ายค้างบันทึก ' || v_wo_count || ' รายการ',
      v_wo_lines,
      'expense_digest',
      v_digest_key
    ) ON CONFLICT DO NOTHING;

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

-- ─── 4. ตรวจสอบผล ─────────────────────────────────
SELECT 'migration_065 OK — requires_expense พร้อมใช้งาน' AS result;
