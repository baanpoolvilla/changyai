-- migration_039_po_rls_assigned_user.sql
-- อนุญาตให้คนที่ได้รับมอบหมาย PO และคนเปิด PR สามารถ update purchase_orders ได้

DROP POLICY IF EXISTS "assigned or creator can update po" ON purchase_orders;

CREATE POLICY "assigned or creator can update po"
  ON purchase_orders
  FOR UPDATE TO authenticated
  USING (
    auth.uid() = po_assigned_to
    OR auth.uid() = created_by
  )
  WITH CHECK (
    auth.uid() = po_assigned_to
    OR auth.uid() = created_by
  );
