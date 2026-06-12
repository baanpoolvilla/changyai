-- =====================================================
-- BaanPool Ops — Migration 045
-- 1. ลบ trg_work_order_status ออกให้แน่ใจ (เปลี่ยนสถานะใบงานไม่ส่ง LINE)
-- 2. แก้/สร้าง trg_notify_pr_created ใหม่ให้แน่ใจว่าแจ้ง CEO เมื่อเปิด PR
-- =====================================================

-- ─────────────────────────────────────────────────────
-- 1. ลบ trigger เปลี่ยนสถานะใบงาน ให้แน่ใจว่าไม่มีอยู่
-- ─────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_work_order_status   ON public.work_orders;
DROP TRIGGER IF EXISTS trg_work_order_status_2 ON public.work_orders;
DROP TRIGGER IF EXISTS work_order_status_trigger ON public.work_orders;

-- ─────────────────────────────────────────────────────
-- 2. สร้าง trg_notify_pr_created ใหม่ (แจ้ง CEO ทุกคน)
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
  v_recipient     RECORD;
BEGIN
  -- ชื่อผู้สร้าง PR
  SELECT full_name INTO v_creator_name
  FROM public.users WHERE id = NEW.created_by;

  -- ชื่อบ้าน
  SELECT name INTO v_property_name
  FROM public.properties WHERE id = NEW.property_id;

  -- สร้างข้อความ
  v_message :=
    '📋 มีการเปิด PR ใหม่' || chr(10)
    || '📦 ' || NEW.title || chr(10)
    || '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
    || '👤 โดย: ' || COALESCE(v_creator_name, '-') || chr(10)
    || '💰 มูลค่า: ' || COALESCE(NEW.total_price::TEXT, '0') || ' บาท' || chr(10)
    || '🔗 https://changyai.vercel.app/purchase-orders';

  -- แจ้ง CEO (role = 'owner') ทุกคน ทาง LINE + in-app
  FOR v_recipient IN
    SELECT id, line_user_id
    FROM public.users
    WHERE role = 'owner'
  LOOP
    -- LINE (ถ้ามี line_user_id)
    IF v_recipient.line_user_id IS NOT NULL AND v_recipient.line_user_id != '' THEN
      PERFORM public.send_line_text(v_recipient.line_user_id, v_message);
    END IF;

    -- In-app notification
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_recipient.id,
      '📋 PR ใหม่: ' || NEW.title,
      '👤 โดย: ' || COALESCE(v_creator_name, '-') || chr(10)
        || '🏠 ' || COALESCE(v_property_name, '-') || chr(10)
        || '💰 ' || COALESCE(NEW.total_price::TEXT, '0') || ' บาท',
      'work_order',
      NEW.id::TEXT
    ) ON CONFLICT DO NOTHING;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pr_created ON public.purchase_orders;
CREATE TRIGGER trg_pr_created
  AFTER INSERT ON public.purchase_orders
  FOR EACH ROW EXECUTE FUNCTION public.trg_notify_pr_created();

-- ─────────────────────────────────────────────────────
-- ตรวจสอบผล
-- ─────────────────────────────────────────────────────
SELECT 'migration_045 OK' AS result;

-- ดู triggers ที่ active บน work_orders (trg_work_order_status ต้องไม่มี)
SELECT trigger_name, event_manipulation
FROM information_schema.triggers
WHERE event_object_table = 'work_orders'
ORDER BY trigger_name;

-- ดู triggers บน purchase_orders (trg_pr_created ต้องมี)
SELECT trigger_name, event_manipulation
FROM information_schema.triggers
WHERE event_object_table = 'purchase_orders'
ORDER BY trigger_name;
