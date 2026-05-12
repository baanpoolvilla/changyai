-- =====================================================
-- BaanPool Ops — Migration 029
-- 1. ลดการแจ้งเตือน LINE: เหลือเฉพาะ "ใบงานใหม่" + "คอมเม้น"
-- 2. สร้าง purchase_orders table (สั่งอุปกรณ์)
-- =====================================================

-- ─── ส่วนที่ 1: ลด LINE notifications ─────────────────

-- 1a. ลบ trigger status change (ส่งทุกครั้งที่สถานะเปลี่ยน → noisy)
DROP TRIGGER IF EXISTS trg_work_order_status ON public.work_orders;

-- 1b. เปลี่ยน trg_work_order_assigned ให้ fire เฉพาะ INSERT
--     (ไม่ส่งซ้ำเมื่อ re-assign)
DROP TRIGGER IF EXISTS trg_work_order_assigned ON public.work_orders;
CREATE TRIGGER trg_work_order_assigned
  AFTER INSERT ON public.work_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_notify_work_order_assigned();

-- ─── ส่วนที่ 2: Purchase Orders ───────────────────────

CREATE TABLE IF NOT EXISTS public.purchase_orders (
  id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  title              TEXT         NOT NULL,
  description        TEXT,
  property_id        UUID         REFERENCES public.properties(id) ON DELETE SET NULL,
  created_by         UUID         REFERENCES public.users(id) ON DELETE SET NULL,
  status             TEXT         NOT NULL DEFAULT 'pending'
                                  CHECK (status IN ('pending','approved','ordered','received','cancelled')),
  items              JSONB        NOT NULL DEFAULT '[]'::jsonb,
  total_price        NUMERIC(12,2) NOT NULL DEFAULT 0,
  notes              TEXT,
  receipt_image_url  TEXT,
  created_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Index for common queries
CREATE INDEX IF NOT EXISTS idx_po_status    ON public.purchase_orders(status);
CREATE INDEX IF NOT EXISTS idx_po_created_by ON public.purchase_orders(created_by);
CREATE INDEX IF NOT EXISTS idx_po_property  ON public.purchase_orders(property_id);

-- updated_at auto-update
CREATE OR REPLACE FUNCTION public.update_po_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;
DROP TRIGGER IF EXISTS trg_po_updated_at ON public.purchase_orders;
CREATE TRIGGER trg_po_updated_at
  BEFORE UPDATE ON public.purchase_orders
  FOR EACH ROW EXECUTE FUNCTION public.update_po_updated_at();

-- ─── RLS ──────────────────────────────────────────────
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='purchase_orders' AND policyname='PO read all') THEN
    CREATE POLICY "PO read all"
      ON public.purchase_orders FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='purchase_orders' AND policyname='PO insert own') THEN
    CREATE POLICY "PO insert own"
      ON public.purchase_orders FOR INSERT TO authenticated
      WITH CHECK (auth.uid() = created_by);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='purchase_orders' AND policyname='PO update') THEN
    CREATE POLICY "PO update"
      ON public.purchase_orders FOR UPDATE TO authenticated
      USING (
        auth.uid() = created_by
        OR EXISTS (
          SELECT 1 FROM public.users
          WHERE id = auth.uid() AND role IN ('admin','owner','manager')
        )
      );
  END IF;
END $$;

-- ─── LINE notification: PO status change ──────────────
CREATE OR REPLACE FUNCTION public.trg_notify_po_status()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_creator_line_id TEXT;
  v_property_name   TEXT;
  v_message         TEXT;
  v_recipient       RECORD;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;

  SELECT name INTO v_property_name
  FROM public.properties WHERE id = NEW.property_id;

  -- CEO อนุมัติ → แจ้งคนสร้าง PO
  IF NEW.status = 'approved' THEN
    SELECT u.line_user_id INTO v_creator_line_id
    FROM public.users u
    WHERE u.id = NEW.created_by
      AND u.line_user_id IS NOT NULL AND u.line_user_id != '';

    IF v_creator_line_id IS NOT NULL THEN
      v_message :=
        '✅ PO ได้รับการอนุมัติแล้ว' || chr(10)
        || '📦 ' || NEW.title || chr(10)
        || '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
        || '🔗 https://changyai.vercel.app/purchase-orders';
      PERFORM public.send_line_text(v_creator_line_id, v_message);
    END IF;
  END IF;

  -- รับของแล้ว → แจ้ง CEO / admin / manager
  IF NEW.status = 'received' THEN
    v_message :=
      '📦 รับอุปกรณ์เรียบร้อย' || chr(10)
      || '🛒 ' || NEW.title || chr(10)
      || '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
      || '💰 รวม: ' || COALESCE(NEW.total_price::TEXT, '-') || ' บาท';

    FOR v_recipient IN
      SELECT DISTINCT line_user_id
      FROM public.users
      WHERE role IN ('owner','admin','manager')
        AND line_user_id IS NOT NULL AND line_user_id != ''
    LOOP
      PERFORM public.send_line_text(v_recipient.line_user_id, v_message);
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_po_status ON public.purchase_orders;
CREATE TRIGGER trg_po_status
  AFTER UPDATE OF status ON public.purchase_orders
  FOR EACH ROW EXECUTE FUNCTION public.trg_notify_po_status();

-- ─── Storage bucket for PO receipts ───────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'po-receipts',
  'po-receipts',
  true,
  10485760,  -- 10 MB
  ARRAY['image/jpeg','image/png','image/webp','image/heic']
) ON CONFLICT (id) DO NOTHING;

-- Storage RLS: allow authenticated to upload
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename='objects' AND schemaname='storage'
      AND policyname='PO receipts upload'
  ) THEN
    CREATE POLICY "PO receipts upload"
      ON storage.objects FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'po-receipts');
    CREATE POLICY "PO receipts read"
      ON storage.objects FOR SELECT TO authenticated
      USING (bucket_id = 'po-receipts');
  END IF;
END $$;

-- ─── ตรวจสอบผล ────────────────────────────────────────
SELECT 'migration_029 OK' AS result;

SELECT trigger_name, event_object_table, event_manipulation
FROM information_schema.triggers
WHERE trigger_name IN ('trg_work_order_assigned','trg_work_order_status','trg_po_status')
ORDER BY trigger_name;
