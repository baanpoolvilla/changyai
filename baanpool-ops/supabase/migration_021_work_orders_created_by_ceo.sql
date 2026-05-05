-- =====================================================
-- BaanPool Ops — Work Orders Created By + CEO Notifications
-- =====================================================
-- 1. Add created_by column to work_orders
-- 2. Update notification triggers so CEO (owner role) only
--    receives notifications for work orders they created
-- =====================================================

-- 1. Add created_by to work_orders
ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_work_orders_created_by
  ON public.work_orders(created_by);

COMMENT ON COLUMN public.work_orders.created_by IS 'ผู้สร้างใบงาน (user_id)';

-- =====================================================
-- 2. Update status-change notification trigger
--    to handle CEO (owner) role — only notify if they created the WO
-- =====================================================
CREATE OR REPLACE FUNCTION public.trg_inapp_notify_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_property RECORD;
  v_tech_name TEXT;
  v_status_text TEXT;
  v_old_status_text TEXT;
  v_admin_user RECORD;
BEGIN
  -- Only fire on status change
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;

  SELECT name INTO v_property FROM public.properties WHERE id = NEW.property_id;

  -- Get technician name
  IF NEW.assigned_to IS NOT NULL THEN
    SELECT full_name INTO v_tech_name FROM public.users WHERE id = NEW.assigned_to;
  END IF;

  CASE NEW.status
    WHEN 'open'        THEN v_status_text := 'เปิด';
    WHEN 'in_progress' THEN v_status_text := 'กำลังดำเนินการ';
    WHEN 'completed'   THEN v_status_text := 'เสร็จแล้ว';
    WHEN 'cancelled'   THEN v_status_text := 'ยกเลิก';
    ELSE                    v_status_text := NEW.status;
  END CASE;

  -- Notify all admin users (Super Admin) for every status change
  FOR v_admin_user IN
    SELECT id FROM public.users WHERE role = 'admin'
  LOOP
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_admin_user.id,
      '🔄 สถานะใบงานเปลี่ยน: ' || NEW.title,
      '🏠 บ้าน: ' || COALESCE(v_property.name, '-') || chr(10)
        || '📋 สถานะ: ' || v_status_text
        || CASE WHEN v_tech_name IS NOT NULL THEN chr(10) || '👤 ช่าง: ' || v_tech_name ELSE '' END,
      'work_order',
      NEW.id::TEXT
    )
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- Notify CEO (owner role) ONLY if they created this work order
  FOR v_admin_user IN
    SELECT id FROM public.users 
    WHERE role = 'owner' 
    AND id = NEW.created_by
  LOOP
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_admin_user.id,
      '🔄 สถานะใบงานเปลี่ยน: ' || NEW.title,
      '🏠 บ้าน: ' || COALESCE(v_property.name, '-') || chr(10)
        || '📋 สถานะ: ' || v_status_text,
      'work_order',
      NEW.id::TEXT
    )
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- Also notify the assigned technician when someone else changes status
  IF NEW.assigned_to IS NOT NULL 
     AND NEW.assigned_to IS DISTINCT FROM NEW.created_by THEN
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      NEW.assigned_to,
      '🔄 สถานะงานเปลี่ยน: ' || NEW.title,
      '📋 สถานะใหม่: ' || v_status_text,
      'work_order',
      NEW.id::TEXT
    )
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- Re-attach the trigger (drop old one first if it exists under old name)
DROP TRIGGER IF EXISTS trg_inapp_notify_status_change ON public.work_orders;
CREATE TRIGGER trg_inapp_notify_status_change
  AFTER UPDATE OF status ON public.work_orders
  FOR EACH ROW EXECUTE FUNCTION public.trg_inapp_notify_status_change();

-- =====================================================
-- 3. Trigger: notify admin + CEO when new work order is created
-- =====================================================
CREATE OR REPLACE FUNCTION public.trg_inapp_notify_work_order_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_property_name TEXT;
  v_priority_label TEXT;
  v_admin_user RECORD;
BEGIN
  SELECT name INTO v_property_name FROM public.properties WHERE id = NEW.property_id;

  CASE COALESCE(NEW.priority, 'medium')
    WHEN 'urgent' THEN v_priority_label := '🔴 เร่งด่วน';
    WHEN 'high'   THEN v_priority_label := '🟠 สูง';
    WHEN 'medium' THEN v_priority_label := '🔵 ปานกลาง';
    WHEN 'low'    THEN v_priority_label := '⚪ ต่ำ';
    ELSE               v_priority_label := NEW.priority;
  END CASE;

  -- Notify all Super Admin (admin role)
  FOR v_admin_user IN
    SELECT id FROM public.users WHERE role = 'admin' AND id != NEW.created_by
  LOOP
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_admin_user.id,
      '📝 ใบงานใหม่: ' || NEW.title,
      '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
        || '⚡ ความสำคัญ: ' || v_priority_label,
      'work_order',
      NEW.id::TEXT
    );
  END LOOP;

  -- Notify CEO (owner role) ONLY if CEO did NOT create this work order
  FOR v_admin_user IN
    SELECT id FROM public.users WHERE role = 'owner' AND id != NEW.created_by
  LOOP
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_admin_user.id,
      '📝 ใบงานใหม่: ' || NEW.title,
      '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
        || '⚡ ความสำคัญ: ' || v_priority_label,
      'work_order',
      NEW.id::TEXT
    );
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_inapp_notify_work_order_created ON public.work_orders;
CREATE TRIGGER trg_inapp_notify_work_order_created
  AFTER INSERT ON public.work_orders
  FOR EACH ROW EXECUTE FUNCTION public.trg_inapp_notify_work_order_created();
