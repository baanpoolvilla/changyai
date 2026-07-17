-- =====================================================
-- BaanPool Ops — Migration 054
-- ใบงานอัตโนมัติจาก PM: รวมแจ้งเตือนเป็นสรุปเดียวต่อคน
--
-- ปัญหา: PM ครบกำหนดพร้อมกัน 15 ใบ มอบให้คนเดียวกัน
--        → trg_work_order_assigned ยิง LINE 15 ข้อความรวด
-- แก้:  ปิดการยิงทีละใบเฉพาะตอน auto-create (flag ระดับ transaction)
--        แล้วส่งสรุป "งานใหม่ 15 รายการ" ครั้งเดียวต่อคน
--
-- ต้องรัน migration 052, 053 ก่อน
-- Run this SQL in Supabase SQL Editor (Dashboard > SQL)
-- =====================================================

-- ─── 1. ให้ trigger ข้ามได้เมื่อยกธง ────────────────
-- ใช้ WHEN clause ที่ตัว trigger — ไม่ต้องแก้ body ของฟังก์ชันเดิม
-- current_setting(..., true) = missing_ok คืน NULL ถ้าไม่ได้ตั้งค่า
DROP TRIGGER IF EXISTS trg_work_order_assigned ON public.work_orders;
CREATE TRIGGER trg_work_order_assigned
  AFTER INSERT OR UPDATE OF assigned_to, cc_user_ids ON public.work_orders
  FOR EACH ROW
  WHEN (COALESCE(current_setting('app.skip_wo_line', true), '') <> 'on')
  EXECUTE FUNCTION public.trg_notify_work_order_assigned();

-- ─── 2. auto-create + สรุปแจ้งเตือนต่อคน ───────────
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
  v_new_id      UUID;
  v_created_ids UUID[] := '{}';
  v_msg         TEXT;
BEGIN
  -- ยกธง: ห้าม trigger ยิง LINE ทีละใบ เดี๋ยวเราส่งสรุปเอง
  PERFORM set_config('app.skip_wo_line', 'on', true); -- true = ผูกกับ transaction

  FOR v_pm IN
    SELECT ps.id, ps.title, ps.description, ps.property_id, ps.asset_id,
           ps.assigned_to, ps.next_due_date,
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
    )
    RETURNING id INTO v_new_id;

    v_created_ids := array_append(v_created_ids, v_new_id);
    v_count := v_count + 1;
  END LOOP;

  -- ลดธงลง เพื่อให้การแจ้งเตือนปกติหลังจากนี้ทำงานตามเดิม
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
