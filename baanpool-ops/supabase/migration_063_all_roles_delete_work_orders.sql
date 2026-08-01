-- =====================================================
-- migration_063 — ให้ทุก role ลบใบงานและความคิดเห็นได้
-- =====================================================
--
-- สถานะเดิม:
--   work_orders          → ไม่มี DELETE policy เลย ทั้งที่ RLS เปิดอยู่
--                          (migration_001 บรรทัด 93) แปลว่าไม่มีใครลบได้จริง
--                          แม้แต่ Super Admin — แต่ Supabase จะตอบว่าสำเร็จ
--                          โดยลบ 0 แถว ทำให้ UI ขึ้นว่า "ลบใบงานแล้ว" หลอก ๆ
--   work_order_comments  → comments_delete ให้ลบได้เฉพาะของตัวเอง
--                          (migration_026 บรรทัด 42)
--
-- หลัง migration นี้: ทุก role ที่ login แล้ว (admin/owner/manager/
-- caretaker/technician) ลบได้ทั้งใบงานและความคิดเห็นของใครก็ได้
--
-- ⚠️ ข้อควรรู้ — FK ที่ชี้มาที่ work_orders เป็น ON DELETE CASCADE ทั้งหมด
--    การลบใบงาน 1 ใบจะลบตามไปด้วย:
--      • work_order_comments        (migration_026 บรรทัด 23)
--      • work_order_external_photos (migration_057 บรรทัด 30)
--      • work_order_upload_links    (migration_057 บรรทัด 14)
--    ส่วน expenses.work_order_id เป็น ON DELETE SET NULL → ค่าใช้จ่ายไม่หาย
--    แต่จะหลุดการผูกกับใบงาน
--    รูปใน Storage ไม่ถูกลบตาม ต้องเก็บกวาดแยกถ้าต้องการคืนพื้นที่
--
-- ปลอดภัยต่อการรันซ้ำ (idempotent)
-- =====================================================

-- ─── 1. ใบงาน — ทุก role ลบได้ ────────────────────────
DROP POLICY IF EXISTS "Anyone authenticated can delete work orders"
  ON public.work_orders;

CREATE POLICY "Anyone authenticated can delete work orders"
  ON public.work_orders FOR DELETE
  TO authenticated
  USING (true);

-- ─── 2. ความคิดเห็นในใบงาน — ทุก role ลบได้ ───────────
-- เดิม USING (auth.uid() = user_id) = ลบได้เฉพาะของตัวเอง
DROP POLICY IF EXISTS "comments_delete" ON public.work_order_comments;

CREATE POLICY "comments_delete"
  ON public.work_order_comments FOR DELETE
  TO authenticated
  USING (true);

-- ─── ตรวจสอบผล ────────────────────────────────────────
SELECT 'migration_063 OK' AS result;

-- ต้องเห็น 2 แถว และคอลัมน์ qual (USING) เป็น true ทั้งคู่
SELECT
  tablename,
  policyname,
  cmd,
  roles,
  qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('work_orders', 'work_order_comments')
  AND cmd = 'DELETE'
ORDER BY tablename;
