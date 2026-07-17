-- =====================================================
-- BaanPool Ops — Migration 056
-- CC ของ PM — ส่งต่อไปยังใบงานที่สร้างอัตโนมัติ
--
-- ตั้ง CC ไว้ที่ PM ครั้งเดียว → ทุกใบงานที่ระบบสร้างจาก PM นั้น
-- จะมี CC ตามไปด้วย (trg_notify_work_order_assigned แจ้ง CC อยู่แล้ว)
--
-- ต้องรัน migration 052-055 ก่อน
-- Run this SQL in Supabase SQL Editor (Dashboard > SQL)
-- =====================================================

ALTER TABLE public.pm_schedules
  ADD COLUMN IF NOT EXISTS cc_user_ids UUID[] DEFAULT '{}';

COMMENT ON COLUMN public.pm_schedules.cc_user_ids IS
  'ผู้รับสำเนาแจ้งเตือน — คัดลอกไปที่ใบงานทุกใบที่สร้างจาก PM นี้';

-- ─── auto-create: ส่ง CC ต่อไปให้ใบงาน + รวมแจ้งเตือน CC ด้วย ─────
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
  v_cc          UUID[];
  v_new_id      UUID;
  v_created_ids UUID[] := '{}';
  v_msg         TEXT;
BEGIN
  -- ยกธง: ห้าม trigger ยิง LINE ทีละใบ เดี๋ยวเราส่งสรุปเอง
  PERFORM set_config('app.skip_wo_line', 'on', true);

  FOR v_pm IN
    SELECT ps.id, ps.title, ps.description, ps.property_id, ps.asset_id,
           ps.assigned_to, ps.next_due_date,
           ps.total_rounds, ps.rounds_done, ps.cc_user_ids,
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

    -- CC จาก PM — ตัดคนที่เป็นผู้รับผิดชอบออก จะได้ไม่แจ้งซ้ำ
    SELECT COALESCE(array_agg(uid), '{}')
    INTO v_cc
    FROM unnest(COALESCE(v_pm.cc_user_ids, '{}')) AS uid
    WHERE uid IS DISTINCT FROM v_assignee;

    v_asset_name := NULL;
    IF v_pm.asset_id IS NOT NULL THEN
      SELECT name INTO v_asset_name FROM public.assets WHERE id = v_pm.asset_id;
    END IF;

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
      status, priority, due_date, pm_schedule_id, auto_created, cc_user_ids
    ) VALUES (
      v_pm.property_id, v_pm.asset_id, v_assignee, v_title, v_desc,
      'open', 'medium', v_pm.next_due_date::timestamptz, v_pm.id, true, v_cc
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
  -- รวมทั้งผู้รับผิดชอบและ CC เข้าด้วยกัน คนที่เป็นทั้งสองอย่างได้ข้อความเดียว
  FOR v_grp IN
    WITH recipients AS (
      -- ผู้รับผิดชอบ
      SELECT wo.id AS wo_id, wo.assigned_to AS user_id, false AS is_cc
      FROM public.work_orders wo
      WHERE wo.id = ANY(v_created_ids) AND wo.assigned_to IS NOT NULL
      UNION
      -- CC
      SELECT wo.id, cc.uid, true
      FROM public.work_orders wo,
           unnest(COALESCE(wo.cc_user_ids, '{}')) AS cc(uid)
      WHERE wo.id = ANY(v_created_ids)
    )
    SELECT r.user_id,
           u.line_user_id,
           count(*)::INT AS n,
           bool_and(r.is_cc) AS all_cc,
           string_agg(
             '• ' || wo.title || ' — ' || p.name,
             chr(10) ORDER BY p.name, wo.title
           ) AS lines
    FROM recipients r
    JOIN public.work_orders wo ON wo.id = r.wo_id
    JOIN public.properties p   ON p.id  = wo.property_id
    JOIN public.users u        ON u.id  = r.user_id
    GROUP BY r.user_id, u.line_user_id
  LOOP
    v_msg := CASE WHEN v_grp.all_cc THEN '📋 (CC) ' ELSE '📢 ' END
          || 'งานใหม่จาก PM'
          || CASE WHEN v_grp.n > 1 THEN ' ' || v_grp.n || ' รายการ' ELSE '' END
          || chr(10) || chr(10) || v_grp.lines
          || chr(10) || chr(10) || 'เข้าดูรายละเอียดที่แอป BaanPool Ops';

    IF v_grp.line_user_id IS NOT NULL AND v_grp.line_user_id <> '' THEN
      PERFORM public.send_line_text(v_grp.line_user_id, v_msg);
    END IF;

    INSERT INTO public.notifications (user_id, title, body, type)
    VALUES (
      v_grp.user_id,
      CASE WHEN v_grp.all_cc THEN '📋 (CC) ' ELSE '📢 ' END
        || 'งานใหม่จาก PM'
        || CASE WHEN v_grp.n > 1 THEN ' ' || v_grp.n || ' รายการ' ELSE '' END,
      v_grp.lines,
      'work_order'
    );
  END LOOP;

  RETURN v_count;
END;
$$;
