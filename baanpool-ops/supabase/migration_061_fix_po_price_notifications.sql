-- =====================================================
-- BaanPool Ops — Migration 061
-- แก้ข้อมูล "ราคา" ในแจ้งเตือน PR/PO ให้ถูกต้อง
--
--  ปัญหาเดิม:
--   1. trg_notify_po_status (อนุมัติ → คนไปซื้อ) ส่ง "💰 วงเงิน: 0 บาท"
--      แต่ตอนอนุมัติราคายังเป็น 0 (กรอกจริงตอนดำเนินการซื้อ) → ไม่มีความหมาย
--   2. trg_notify_pr_created (เปิด PR → CEO) ส่ง "💰 มูลค่า: 0 บาท"
--      สำหรับ PR ปกติที่ยังไม่มีราคา
--
--  แก้เป็น:
--   1. เอาบรรทัดราคา/วงเงินออกจากแจ้งเตือนตอนอนุมัติ (คนซื้อกรอกราคาเอง)
--   2. แสดง "💰 ราคา: X บาท" เฉพาะเมื่อมีราคาจริง (total_price > 0)
-- =====================================================

-- ─────────────────────────────────────────────────────
-- 1. trg_notify_po_status: อนุมัติ → คนไปซื้อ (ไม่ต้องมีราคา)
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_notify_po_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_assignee_line TEXT;
  v_property_name TEXT;
  v_message       TEXT;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;

  -- ดึงชื่อบ้าน
  SELECT name INTO v_property_name
  FROM public.properties WHERE id = NEW.property_id;

  -- CEO อนุมัติ → แจ้ง po_assigned_to (คนที่จะไปซื้อ) — ไม่ส่งราคา
  IF NEW.status = 'approved' AND NEW.po_assigned_to IS NOT NULL THEN
    SELECT u.line_user_id INTO v_assignee_line
    FROM public.users u
    WHERE u.id = NEW.po_assigned_to
      AND u.line_user_id IS NOT NULL AND u.line_user_id != '';

    IF v_assignee_line IS NOT NULL THEN
      v_message :=
        '✅ PR ได้รับการอนุมัติแล้ว — กรุณาจัดซื้อ' || chr(10)
        || '📦 ' || NEW.title || chr(10)
        || '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
        || '🔗 https://changyai.vercel.app/purchase-orders';
      PERFORM public.send_line_text(v_assignee_line, v_message);
    END IF;
  END IF;

  -- หากไม่มี po_assigned_to แต่ approved → แจ้ง created_by
  IF NEW.status = 'approved' AND NEW.po_assigned_to IS NULL THEN
    SELECT u.line_user_id INTO v_assignee_line
    FROM public.users u
    WHERE u.id = NEW.created_by
      AND u.line_user_id IS NOT NULL AND u.line_user_id != '';

    IF v_assignee_line IS NOT NULL THEN
      v_message :=
        '✅ PR ได้รับการอนุมัติแล้ว' || chr(10)
        || '📦 ' || NEW.title || chr(10)
        || '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
        || '🔗 https://changyai.vercel.app/purchase-orders';
      PERFORM public.send_line_text(v_assignee_line, v_message);
    END IF;
  END IF;

  -- received / cancelled → ไม่มี LINE notification

  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────
-- 2. trg_notify_pr_created: เปิด PR → CEO
--    แสดงราคาเฉพาะเมื่อมีราคาจริง (> 0) เช่น PR ฉุกเฉิน
--    (คงตรรกะ fallback line_user_id จาก email ไว้เหมือนเดิม)
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_notify_pr_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_creator_name  TEXT;
  v_property_name TEXT;
  v_message       TEXT;
  v_price_line    TEXT;
  v_price_inapp   TEXT;
  v_recipient     RECORD;
BEGIN
  -- ชื่อผู้สร้าง PR
  SELECT full_name INTO v_creator_name
  FROM public.users WHERE id = NEW.created_by;

  -- ชื่อบ้าน
  SELECT name INTO v_property_name
  FROM public.properties WHERE id = NEW.property_id;

  -- แสดงราคาเฉพาะเมื่อมีราคาจริง (total_price > 0)
  IF COALESCE(NEW.total_price, 0) > 0 THEN
    v_price_line  := '💰 ราคา: ' || NEW.total_price::TEXT || ' บาท' || chr(10);
    v_price_inapp := chr(10) || '💰 ' || NEW.total_price::TEXT || ' บาท';
  ELSE
    v_price_line  := '';
    v_price_inapp := '';
  END IF;

  -- สร้างข้อความ LINE
  v_message :=
    '📋 มีการเปิด PR ใหม่' || chr(10)
    || '📦 ' || NEW.title || chr(10)
    || '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
    || '👤 โดย: ' || COALESCE(v_creator_name, '-') || chr(10)
    || v_price_line
    || '🔗 https://changyai.vercel.app/purchase-orders';

  -- แจ้ง CEO (role = 'owner') ทุกคน ทาง LINE + in-app
  FOR v_recipient IN
    SELECT id,
           COALESCE(
             NULLIF(line_user_id, ''),
             CASE WHEN email LIKE 'line_%@changyai.app'
               THEN NULLIF(split_part(split_part(email, '@', 1), 'line_', 2), '')
               ELSE NULL
             END
           ) AS effective_line_id
    FROM public.users
    WHERE role = 'owner'
  LOOP
    -- LINE
    IF v_recipient.effective_line_id IS NOT NULL THEN
      PERFORM public.send_line_text(v_recipient.effective_line_id, v_message);
    END IF;

    -- In-app notification
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_recipient.id,
      '📋 PR ใหม่: ' || NEW.title,
      '👤 โดย: ' || COALESCE(v_creator_name, '-') || chr(10)
        || '🏠 ' || COALESCE(v_property_name, '-')
        || v_price_inapp,
      'work_order',
      NEW.id::TEXT
    ) ON CONFLICT DO NOTHING;
  END LOOP;

  RETURN NEW;
END;
$$;

SELECT 'migration_061 OK' AS result;
