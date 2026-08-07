-- =====================================================
-- BaanPool Ops — Migration 066
-- ช่างภายนอกพิมพ์ข้อความแนบมากับรูปได้
--
-- เดิมลิงก์สาธารณะส่งได้แต่รูป ช่างเลยบอกรายละเอียดงานไม่ได้เลย
-- (เช่น "เปลี่ยนคาปาซิเตอร์ตัวใหม่แล้ว" / "ต้องสั่งอะไหล่เพิ่ม")
-- เพิ่มคอลัมน์ note ที่รูปแต่ละใบ แล้วให้ RPC รับข้อความมาพร้อมกัน
-- =====================================================

ALTER TABLE public.work_order_external_photos
  ADD COLUMN IF NOT EXISTS note TEXT;

-- แทนที่เวอร์ชัน 2 อาร์กิวเมนต์ของ migration 057 (ไม่เก็บไว้เป็น overload
-- เพราะจะกำกวมตอน PostgREST เลือกฟังก์ชันจากชื่อพารามิเตอร์)
DROP FUNCTION IF EXISTS public.register_external_work_order_photo(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.register_external_work_order_photo(
  p_token TEXT,
  p_storage_path TEXT,
  p_note TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage, extensions
AS $$
DECLARE
  v_link public.work_order_upload_links%ROWTYPE;
  v_photo_id UUID;
  v_note TEXT;
BEGIN
  IF p_token !~ '^[0-9a-f]{64}$'
     OR p_storage_path NOT LIKE 'external-work-orders/' || p_token || '/%' THEN
    RAISE EXCEPTION 'Invalid upload token or path';
  END IF;

  -- ตัดความยาวกันคนนอกยัดข้อความยาวผิดปกติเข้ามา
  v_note := NULLIF(BTRIM(LEFT(COALESCE(p_note, ''), 500)), '');

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
    work_order_id, upload_link_id, storage_path, note
  ) VALUES (
    v_link.work_order_id, v_link.id, p_storage_path, v_note
  )
  RETURNING id INTO v_photo_id;

  RETURN v_photo_id;
END;
$$;

REVOKE ALL ON FUNCTION public.register_external_work_order_photo(TEXT, TEXT, TEXT)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_external_work_order_photo(TEXT, TEXT, TEXT)
  TO anon, authenticated;
