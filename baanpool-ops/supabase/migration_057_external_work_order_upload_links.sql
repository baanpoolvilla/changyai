-- =====================================================
-- BaanPool Ops — Migration 057
-- Public photo-only upload links for external technicians.
--
-- ผู้ใช้ในระบบสร้างลิงก์จากหน้าใบงาน แล้วส่งให้ช่างภายนอกได้
-- ช่างไม่ต้อง login และทำได้เฉพาะอัปโหลดรูปให้ใบงานนั้น
-- ลิงก์หมดอายุใน 7 วัน, จำกัด 20 รูป และใช้ไม่ได้เมื่อใบงานปิด/ยกเลิก
-- =====================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE TABLE IF NOT EXISTS public.work_order_upload_links (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_id UUID NOT NULL REFERENCES public.work_orders(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL UNIQUE,
  created_by  UUID REFERENCES public.users(id) ON DELETE SET NULL,
  expires_at  TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
  max_uploads INT NOT NULL DEFAULT 20 CHECK (max_uploads BETWEEN 1 AND 50),
  revoked_at  TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wo_upload_links_work_order
  ON public.work_order_upload_links(work_order_id);
CREATE INDEX IF NOT EXISTS idx_wo_upload_links_token_hash
  ON public.work_order_upload_links(token_hash);

CREATE TABLE IF NOT EXISTS public.work_order_external_photos (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_id  UUID NOT NULL REFERENCES public.work_orders(id) ON DELETE CASCADE,
  upload_link_id UUID NOT NULL REFERENCES public.work_order_upload_links(id) ON DELETE CASCADE,
  storage_path   TEXT NOT NULL UNIQUE,
  uploaded_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wo_external_photos_work_order
  ON public.work_order_external_photos(work_order_id, uploaded_at);

ALTER TABLE public.work_order_upload_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_order_external_photos ENABLE ROW LEVEL SECURITY;

-- ผู้ใช้ที่ RLS ของ work_orders อนุญาตให้เห็นใบงาน จะเห็นรูปภายนอกของใบนั้นได้
DROP POLICY IF EXISTS "work_order_members_read_external_photos"
  ON public.work_order_external_photos;
CREATE POLICY "work_order_members_read_external_photos"
  ON public.work_order_external_photos
  FOR SELECT TO authenticated
  USING (
    work_order_id IN (SELECT id FROM public.work_orders)
  );

-- สร้าง token ใหม่ทุกครั้งและ revoke token เดิมของใบงานนั้น
CREATE OR REPLACE FUNCTION public.create_work_order_upload_link(
  p_work_order_id UUID
)
RETURNS TABLE(token TEXT, expires_at TIMESTAMPTZ, max_uploads INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_work_order public.work_orders%ROWTYPE;
  v_token TEXT;
  v_expires_at TIMESTAMPTZ := NOW() + INTERVAL '7 days';
  v_allowed BOOLEAN := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT * INTO v_work_order
  FROM public.work_orders
  WHERE id = p_work_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Work order not found';
  END IF;

  IF v_work_order.status IN ('completed', 'cancelled') THEN
    RAISE EXCEPTION 'Cannot create a link for a closed work order';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND u.role IN ('admin', 'owner', 'manager')
  )
  OR v_work_order.assigned_to = auth.uid()
  OR v_work_order.created_by = auth.uid()
  OR EXISTS (
    SELECT 1
    FROM public.properties p
    WHERE p.caretaker_id = auth.uid()
      AND (
        p.id = v_work_order.property_id
        OR p.id = ANY(COALESCE(v_work_order.additional_property_ids, '{}'))
      )
  ) INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Not allowed to create an upload link for this work order';
  END IF;

  UPDATE public.work_order_upload_links
  SET revoked_at = NOW()
  WHERE work_order_id = p_work_order_id
    AND revoked_at IS NULL;

  v_token := encode(gen_random_bytes(32), 'hex');

  INSERT INTO public.work_order_upload_links (
    work_order_id, token_hash, created_by, expires_at, max_uploads
  ) VALUES (
    p_work_order_id,
    encode(digest(v_token, 'sha256'), 'hex'),
    auth.uid(),
    v_expires_at,
    20
  );

  RETURN QUERY SELECT v_token, v_expires_at, 20;
END;
$$;

-- คืนเฉพาะข้อมูลที่ช่างจำเป็นต้องเห็น ไม่เปิดรายละเอียด/ผู้ใช้/สถานะภายใน
CREATE OR REPLACE FUNCTION public.get_external_upload_context(
  p_token TEXT
)
RETURNS TABLE(
  work_order_title TEXT,
  property_name TEXT,
  expires_at TIMESTAMPTZ,
  upload_count INT,
  max_uploads INT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT
    wo.title,
    p.name,
    l.expires_at,
    (SELECT COUNT(*)::INT
     FROM public.work_order_external_photos ep
     WHERE ep.upload_link_id = l.id),
    l.max_uploads
  FROM public.work_order_upload_links l
  JOIN public.work_orders wo ON wo.id = l.work_order_id
  JOIN public.properties p ON p.id = wo.property_id
  WHERE p_token ~ '^[0-9a-f]{64}$'
    AND l.token_hash = encode(digest(p_token, 'sha256'), 'hex')
    AND l.revoked_at IS NULL
    AND l.expires_at > NOW()
    AND wo.status NOT IN ('completed', 'cancelled')
  LIMIT 1;
$$;

-- Storage RLS เรียก helper นี้เพื่อตรวจ path/token โดยไม่เปิดตารางลิงก์ให้ anon
CREATE OR REPLACE FUNCTION public.can_external_work_order_upload(
  p_storage_path TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.work_order_upload_links l
    JOIN public.work_orders wo ON wo.id = l.work_order_id
    WHERE p_storage_path ~ '^external-work-orders/[0-9a-f]{64}/[^/]+$'
      AND l.token_hash = encode(
        digest(split_part(p_storage_path, '/', 2), 'sha256'),
        'hex'
      )
      AND l.revoked_at IS NULL
      AND l.expires_at > NOW()
      AND wo.status NOT IN ('completed', 'cancelled')
      AND (
        SELECT COUNT(*)
        FROM public.work_order_external_photos ep
        WHERE ep.upload_link_id = l.id
      ) < l.max_uploads
  );
$$;

-- หลัง Storage รับไฟล์แล้ว บันทึกความสัมพันธ์กับใบงาน
CREATE OR REPLACE FUNCTION public.register_external_work_order_photo(
  p_token TEXT,
  p_storage_path TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage, extensions
AS $$
DECLARE
  v_link public.work_order_upload_links%ROWTYPE;
  v_photo_id UUID;
BEGIN
  IF p_token !~ '^[0-9a-f]{64}$'
     OR p_storage_path NOT LIKE 'external-work-orders/' || p_token || '/%' THEN
    RAISE EXCEPTION 'Invalid upload token or path';
  END IF;

  SELECT l.* INTO v_link
  FROM public.work_order_upload_links l
  JOIN public.work_orders wo ON wo.id = l.work_order_id
  WHERE l.token_hash = encode(digest(p_token, 'sha256'), 'hex')
    AND l.revoked_at IS NULL
    AND l.expires_at > NOW()
    AND wo.status NOT IN ('completed', 'cancelled')
  FOR UPDATE OF l;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Upload link is invalid or expired';
  END IF;

  IF (SELECT COUNT(*) FROM public.work_order_external_photos
      WHERE upload_link_id = v_link.id) >= v_link.max_uploads THEN
    RAISE EXCEPTION 'Upload limit reached';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM storage.objects
    WHERE bucket_id = 'photos' AND name = p_storage_path
  ) THEN
    RAISE EXCEPTION 'Uploaded file not found';
  END IF;

  INSERT INTO public.work_order_external_photos (
    work_order_id, upload_link_id, storage_path
  ) VALUES (
    v_link.work_order_id, v_link.id, p_storage_path
  )
  RETURNING id INTO v_photo_id;

  RETURN v_photo_id;
END;
$$;

-- ใบงานปิดแล้ว revoke ลิงก์ทันที (นอกจาก validation ที่เช็ค status อยู่แล้ว)
CREATE OR REPLACE FUNCTION public.trg_revoke_work_order_upload_links()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('completed', 'cancelled')
     AND OLD.status IS DISTINCT FROM NEW.status THEN
    UPDATE public.work_order_upload_links
    SET revoked_at = COALESCE(revoked_at, NOW())
    WHERE work_order_id = NEW.id AND revoked_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_revoke_work_order_upload_links ON public.work_orders;
CREATE TRIGGER trg_revoke_work_order_upload_links
  AFTER UPDATE OF status ON public.work_orders
  FOR EACH ROW EXECUTE FUNCTION public.trg_revoke_work_order_upload_links();

DROP POLICY IF EXISTS "Anonymous external work order photo upload"
  ON storage.objects;
CREATE POLICY "Anonymous external work order photo upload"
  ON storage.objects
  FOR INSERT TO anon
  WITH CHECK (
    bucket_id = 'photos'
    AND lower(storage.extension(name)) IN ('jpg', 'jpeg', 'png', 'webp', 'heic')
    AND COALESCE((metadata->>'size')::BIGINT, 0) <= 10485760
    AND public.can_external_work_order_upload(name)
  );

-- SECURITY DEFINER functions are executable by PUBLIC unless explicitly revoked.
REVOKE ALL ON FUNCTION public.create_work_order_upload_link(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_work_order_upload_link(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.get_external_upload_context(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_external_upload_context(TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.can_external_work_order_upload(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_external_work_order_upload(TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.register_external_work_order_photo(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_external_work_order_photo(TEXT, TEXT)
  TO anon, authenticated;

REVOKE ALL ON FUNCTION public.trg_revoke_work_order_upload_links() FROM PUBLIC;
