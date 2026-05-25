-- =====================================================
-- BaanPool Ops — Migration 035
-- Reassert caretaker permissions for adding/updating assets
-- in their assigned properties.
-- =====================================================

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

DROP POLICY IF EXISTS "Caretaker can update assets for own properties" ON public.assets;
CREATE POLICY "Caretaker can update assets for own properties"
  ON public.assets FOR UPDATE
  TO authenticated
  USING (
    public.get_user_role() = 'caretaker'
    AND property_id IN (
      SELECT id FROM public.properties WHERE caretaker_id = auth.uid()
    )
  );