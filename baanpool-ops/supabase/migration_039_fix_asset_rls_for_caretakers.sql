-- =====================================================
-- BaanPool Ops — Migration 039
-- Fix asset RLS so caretakers can add/update assets
-- only for properties assigned to them.
-- =====================================================

-- Reassert admin/owner/manager asset management with explicit WITH CHECK.
DROP POLICY IF EXISTS "Manager+ can manage assets" ON public.assets;
DROP POLICY IF EXISTS "Admin/Manager+ can manage assets" ON public.assets;
CREATE POLICY "Admin/Manager+ can manage assets"
  ON public.assets FOR ALL
  TO authenticated
  USING (public.get_user_role() IN ('admin', 'owner', 'manager'))
  WITH CHECK (public.get_user_role() IN ('admin', 'owner', 'manager'));

-- Caretaker can view assets belonging to properties they manage.
DROP POLICY IF EXISTS "Caretaker can view own property assets" ON public.assets;
CREATE POLICY "Caretaker can view own property assets"
  ON public.assets FOR SELECT
  TO authenticated
  USING (
    property_id IN (
      SELECT id FROM public.properties WHERE caretaker_id = auth.uid()
    )
  );

-- Caretaker can insert assets for their assigned properties.
DROP POLICY IF EXISTS "Caretaker can insert assets for own properties" ON public.assets;
CREATE POLICY "Caretaker can insert assets for own properties"
  ON public.assets FOR INSERT
  TO authenticated
  WITH CHECK (
    public.get_user_role() = 'caretaker'
    AND property_id IN (
      SELECT id FROM public.properties WHERE caretaker_id = auth.uid()
    )
  );

-- Caretaker can update assets for their assigned properties.
DROP POLICY IF EXISTS "Caretaker can update assets for own properties" ON public.assets;
CREATE POLICY "Caretaker can update assets for own properties"
  ON public.assets FOR UPDATE
  TO authenticated
  USING (
    public.get_user_role() = 'caretaker'
    AND property_id IN (
      SELECT id FROM public.properties WHERE caretaker_id = auth.uid()
    )
  )
  WITH CHECK (
    public.get_user_role() = 'caretaker'
    AND property_id IN (
      SELECT id FROM public.properties WHERE caretaker_id = auth.uid()
    )
  );