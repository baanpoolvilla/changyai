-- =====================================================
-- migration_064 — ลบ comment ของ PO ได้ + เก็บกวาดรูปใน Storage
-- =====================================================
--
-- ต่อจาก migration_063 ที่เปิดให้ทุก role ลบใบงาน/ความคิดเห็นในใบงาน
-- ไฟล์นี้เพิ่มอีก 2 อย่าง:
--
--   1. purchase_order_comments — เดิมมีแค่ policy SELECT กับ INSERT
--      (migration_036) ไม่มี DELETE เลย = ลบ comment ใน PO ไม่ได้
--
--   2. Storage bucket po-receipts — เดิมมีแค่ policy upload กับ read
--      (migration_029) พอลบ comment ทิ้ง รูปจะค้างกินพื้นที่ตลอดไป
--      ซึ่งสำคัญมากเพราะโปรเจกต์อยู่บน Free Plan (โควตา 1 GB)
--
-- ⚠️ policy ข้อ 2 ให้สิทธิ์ผู้ใช้ที่ login แล้ว "ทุกคน" ลบไฟล์ใดก็ได้
--    ใน bucket po-receipts (รวมใบเสร็จ PO ที่ไม่ใช่ของตัวเอง)
--    เป็นระดับสิทธิ์เดียวกับที่ bucket photos ใช้อยู่แล้วตั้งแต่
--    migration_005 ("Allow authenticated delete")
--
-- ปลอดภัยต่อการรันซ้ำ (idempotent)
-- =====================================================

-- ─── 1. comment ใน PO — ทุก role ลบได้ ────────────────
DROP POLICY IF EXISTS "authenticated can delete po_comments"
  ON public.purchase_order_comments;

CREATE POLICY "authenticated can delete po_comments"
  ON public.purchase_order_comments FOR DELETE
  TO authenticated
  USING (true);

-- ─── 2. ลบไฟล์ใน bucket po-receipts ได้ ───────────────
-- ต้องมี ไม่งั้นแอปลบรูปตามไม่ได้ และ Supabase จะไม่ฟ้อง error
-- (storage.remove ที่โดน RLS บล็อกจะเงียบเหมือน .delete())
DROP POLICY IF EXISTS "PO receipts delete" ON storage.objects;

CREATE POLICY "PO receipts delete"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'po-receipts');

-- ─── ตรวจสอบผล ────────────────────────────────────────
SELECT 'migration_064 OK' AS result;

-- ต้องเห็น DELETE policy ครบทั้ง 4 ตัว (นับรวมของ migration_063 ด้วย)
SELECT
  schemaname,
  tablename,
  policyname,
  cmd,
  qual
FROM pg_policies
WHERE cmd = 'DELETE'
  AND (
    (schemaname = 'public'
      AND tablename IN ('work_orders', 'work_order_comments',
                        'purchase_order_comments'))
    OR (schemaname = 'storage' AND policyname = 'PO receipts delete')
  )
ORDER BY schemaname, tablename, policyname;
