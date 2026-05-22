-- migration_036_po_comments.sql
-- ตาราง comment สำหรับ Purchase Order (PR/PO)

CREATE TABLE IF NOT EXISTS purchase_order_comments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  purchase_order_id UUID REFERENCES purchase_orders(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES users(id),
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

ALTER TABLE purchase_order_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated can read po_comments"
  ON purchase_order_comments FOR SELECT
  TO authenticated USING (true);

CREATE POLICY "authenticated can insert own po_comments"
  ON purchase_order_comments FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);
