-- =====================================================
-- BaanPool Ops — Migration 055
-- PM แบบจำกัดจำนวนครั้ง (เช่น ฉีดปลวก 6 ครั้งจบสัญญา)
--
-- ต่างจาก PM เดิมตรงที่ "ไม่มีความถี่" — นัดวันทีละครั้ง
-- จบครั้งหนึ่ง → สถานะ "รอนัดวัน" (awaiting_schedule) จนกว่าคนจะไปนัดวันใหม่
-- ครบจำนวนครั้ง → ปิด PM (is_active = false)
--
-- ประเภท PM แยกจากข้อมูล ไม่ต้องมีคอลัมน์ enum:
--   total_rounds    IS NOT NULL → แบบจำกัดจำนวนครั้ง
--   rounds_per_year IS NOT NULL → แบบรอบต่อปี
--   ไม่มีทั้งคู่                → แบบต่อเนื่อง
--
-- ต้องรัน migration 052-054 ก่อน
-- Run this SQL in Supabase SQL Editor (Dashboard > SQL)
-- =====================================================

-- ─── 1. คอลัมน์ใหม่ ────────────────────────────────
ALTER TABLE public.pm_schedules
  ADD COLUMN IF NOT EXISTS total_rounds INT,
  ADD COLUMN IF NOT EXISTS rounds_done INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS awaiting_schedule BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.pm_schedules.total_rounds IS
  'จำนวนครั้งทั้งหมดที่ต้องทำ (เช่น ฉีดปลวก 6 ครั้ง) — NULL = ทำไม่จำกัด';
COMMENT ON COLUMN public.pm_schedules.rounds_done IS
  'ทำไปแล้วกี่ครั้ง — ใช้คู่กับ total_rounds';
COMMENT ON COLUMN public.pm_schedules.awaiting_schedule IS
  'true = จบครั้งล่าสุดแล้ว รอคนนัดวันครั้งถัดไป (ห้ามสร้างใบงานอัตโนมัติระหว่างนี้)';

-- total_rounds ต้องอย่างน้อย 1
ALTER TABLE public.pm_schedules
  DROP CONSTRAINT IF EXISTS pm_schedules_total_rounds_check;
ALTER TABLE public.pm_schedules
  ADD CONSTRAINT pm_schedules_total_rounds_check
  CHECK (total_rounds IS NULL OR total_rounds >= 1);

-- ประเภท PM ต้องไม่ซ้อนกัน: จำกัดครั้ง กับ รอบต่อปี เลือกได้อย่างเดียว
ALTER TABLE public.pm_schedules
  DROP CONSTRAINT IF EXISTS pm_schedules_mode_check;
ALTER TABLE public.pm_schedules
  ADD CONSTRAINT pm_schedules_mode_check
  CHECK (NOT (total_rounds IS NOT NULL AND rounds_per_year IS NOT NULL));

-- ─── 2. auto-create: ข้าม PM ที่รอนัดวัน + ใส่ "ครั้งที่ N/M" ─────
CREATE OR REPLACE FUNCTION public.auto_create_pm_work_orders()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pm          RECORD;
  v_grp         RECORD;
  v_count       INT := 0;
  v_assignee    UUID;
  v_asset_name  TEXT;
  v_desc        TEXT;
  v_title       TEXT;
  v_round_txt   TEXT;
  v_new_id      UUID;
  v_created_ids UUID[] := '{}';
  v_msg         TEXT;
BEGIN
  -- ยกธง: ห้าม trigger ยิง LINE ทีละใบ เดี๋ยวเราส่งสรุปเอง
  PERFORM set_config('app.skip_wo_line', 'on', true);

  FOR v_pm IN
    SELECT ps.id, ps.title, ps.description, ps.property_id, ps.asset_id,
           ps.assigned_to, ps.next_due_date,
           ps.total_rounds, ps.rounds_done,
           p.caretaker_id, p.name AS property_name
    FROM public.pm_schedules ps
    JOIN public.properties p ON p.id = ps.property_id
    WHERE ps.is_active = true
      AND ps.awaiting_schedule = false   -- รอนัดวันอยู่ → ยังไม่สร้าง
      AND ps.next_due_date <= CURRENT_DATE
      AND NOT EXISTS (
        SELECT 1 FROM public.work_orders wo
        WHERE wo.pm_schedule_id = ps.id
          AND wo.status NOT IN ('completed', 'cancelled')
      )
  LOOP
    v_assignee := COALESCE(v_pm.assigned_to, v_pm.caretaker_id);

    v_asset_name := NULL;
    IF v_pm.asset_id IS NOT NULL THEN
      SELECT name INTO v_asset_name FROM public.assets WHERE id = v_pm.asset_id;
    END IF;

    -- PM แบบจำกัดจำนวนครั้ง → ใส่ "(ครั้งที่ 2/6)" ต่อท้ายชื่องาน
    IF v_pm.total_rounds IS NOT NULL THEN
      v_round_txt := ' (ครั้งที่ ' || (v_pm.rounds_done + 1)
                  || '/' || v_pm.total_rounds || ')';
    ELSE
      v_round_txt := '';
    END IF;
    v_title := v_pm.title || v_round_txt;

    v_desc := 'PM: ' || v_pm.title || v_round_txt
           || E'\nบ้าน: '   || v_pm.property_name
           || COALESCE(E'\nอุปกรณ์: ' || v_asset_name, '')
           || E'\nกำหนด: '  || to_char(v_pm.next_due_date, 'DD/MM/YYYY')
           || COALESCE(E'\nรายละเอียด: ' || v_pm.description, '')
           || E'\n\n(ใบงานนี้ระบบสร้างอัตโนมัติจาก PM)';

    INSERT INTO public.work_orders (
      property_id, asset_id, assigned_to, title, description,
      status, priority, due_date, pm_schedule_id, auto_created
    ) VALUES (
      v_pm.property_id, v_pm.asset_id, v_assignee, v_title, v_desc,
      'open', 'medium', v_pm.next_due_date::timestamptz, v_pm.id, true
    )
    RETURNING id INTO v_new_id;

    v_created_ids := array_append(v_created_ids, v_new_id);
    v_count := v_count + 1;
  END LOOP;

  PERFORM set_config('app.skip_wo_line', 'off', true);

  IF v_count = 0 THEN
    RETURN 0;
  END IF;

  -- ─── สรุปต่อคน: 1 คน = 1 ข้อความ ────────────────
  FOR v_grp IN
    SELECT wo.assigned_to AS user_id,
           u.line_user_id,
           count(*)::INT AS n,
           string_agg(
             '• ' || wo.title || ' — ' || p.name,
             chr(10) ORDER BY p.name, wo.title
           ) AS lines
    FROM public.work_orders wo
    JOIN public.properties p ON p.id = wo.property_id
    JOIN public.users u      ON u.id = wo.assigned_to
    WHERE wo.id = ANY(v_created_ids)
      AND wo.assigned_to IS NOT NULL
    GROUP BY wo.assigned_to, u.line_user_id
  LOOP
    IF v_grp.n = 1 THEN
      v_msg := '📢 งานใหม่จาก PM' || chr(10) || chr(10) || v_grp.lines;
    ELSE
      v_msg := '📢 งานใหม่จาก PM ' || v_grp.n || ' รายการ'
            || chr(10) || chr(10) || v_grp.lines;
    END IF;
    v_msg := v_msg || chr(10) || chr(10) || 'เข้าดูรายละเอียดที่แอป BaanPool Ops';

    IF v_grp.line_user_id IS NOT NULL AND v_grp.line_user_id <> '' THEN
      PERFORM public.send_line_text(v_grp.line_user_id, v_msg);
    END IF;

    INSERT INTO public.notifications (user_id, title, body, type)
    VALUES (
      v_grp.user_id,
      CASE WHEN v_grp.n = 1
        THEN '📢 งานใหม่จาก PM'
        ELSE '📢 งานใหม่จาก PM ' || v_grp.n || ' รายการ'
      END,
      v_grp.lines,
      'work_order'
    );
  END LOOP;

  RETURN v_count;
END;
$$;
