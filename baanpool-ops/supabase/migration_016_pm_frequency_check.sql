-- Migration 016: Update pm_schedules frequency CHECK constraint
-- Allow new granular frequency values alongside legacy ones

ALTER TABLE public.pm_schedules DROP CONSTRAINT IF EXISTS pm_schedules_frequency_check;

ALTER TABLE public.pm_schedules ADD CONSTRAINT pm_schedules_frequency_check
  CHECK (frequency IN (
    'weekly', 'biweekly', 'triweekly',
    'monthly', 'bimonthly', 'quarterly',
    'month4', 'month5', 'semiannual',
    'month7', 'month8', 'month9',
    'month10', 'month11', 'annual'
  ));
