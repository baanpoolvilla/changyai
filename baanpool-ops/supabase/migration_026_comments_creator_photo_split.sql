-- =====================================================
-- BaanPool Ops — Migration 026
-- 1. Split photo_urls into before/after
-- 2. Creator tracking for pm_schedules & expenses
-- 3. Work order comments table
-- =====================================================

-- ─── 1. Work Orders: add after_photo_urls ─────────
ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS after_photo_urls TEXT[] DEFAULT '{}';

-- ─── 2. PM Schedules: add created_by ──────────────
ALTER TABLE public.pm_schedules
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.users(id) ON DELETE SET NULL;

-- ─── 3. Expenses: add created_by ──────────────────
ALTER TABLE public.expenses
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.users(id) ON DELETE SET NULL;

-- ─── 4. Work Order Comments ───────────────────────
CREATE TABLE IF NOT EXISTS public.work_order_comments (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  work_order_id UUID NOT NULL REFERENCES public.work_orders(id) ON DELETE CASCADE,
  user_id      UUID REFERENCES public.users(id) ON DELETE SET NULL,
  content      TEXT NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── 5. RLS for work_order_comments ───────────────
ALTER TABLE public.work_order_comments ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read comments
CREATE POLICY "comments_select" ON public.work_order_comments
  FOR SELECT TO authenticated USING (true);

-- Authenticated users can insert their own comments
CREATE POLICY "comments_insert" ON public.work_order_comments
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- Users can delete only their own comments (admins handled separately)
CREATE POLICY "comments_delete" ON public.work_order_comments
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

-- ─── 6. Indexes ──────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_work_order_comments_work_order_id
  ON public.work_order_comments(work_order_id);

CREATE INDEX IF NOT EXISTS idx_work_orders_after_photo_urls
  ON public.work_orders USING GIN (after_photo_urls);
