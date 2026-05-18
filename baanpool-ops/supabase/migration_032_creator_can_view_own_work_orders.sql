-- Migration 032: Allow work order creators to always see their own work orders
-- Previously, a user who created a work order but was not assigned and not a caretaker
-- of the property could not see it via RLS. This adds a policy so creators always
-- have SELECT access to their own work orders.

DROP POLICY IF EXISTS "Creator can view own work orders" ON public.work_orders;
CREATE POLICY "Creator can view own work orders"
  ON public.work_orders FOR SELECT
  TO authenticated
  USING (created_by = auth.uid());
