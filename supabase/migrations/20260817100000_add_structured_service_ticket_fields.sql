-- T6.2: Add structured fields for biomedical service intake on public.service_tickets.
-- Local-only migration; do not push without review.

ALTER TABLE public.service_tickets
  ADD COLUMN IF NOT EXISTS equipment_name text,
  ADD COLUMN IF NOT EXISTS equipment_brand text,
  ADD COLUMN IF NOT EXISTS equipment_model text,
  ADD COLUMN IF NOT EXISTS serial_number text,
  ADD COLUMN IF NOT EXISTS institution text,
  ADD COLUMN IF NOT EXISTS department text,
  ADD COLUMN IF NOT EXISTS equipment_operating boolean,
  ADD COLUMN IF NOT EXISTS failure_description text,
  ADD COLUMN IF NOT EXISTS intake_details jsonb;
COMMENT ON COLUMN public.service_tickets.equipment_name IS 'Snapshot of the equipment/device name provided during service intake.';
COMMENT ON COLUMN public.service_tickets.equipment_brand IS 'Snapshot of the equipment brand/manufacturer provided during service intake.';
COMMENT ON COLUMN public.service_tickets.equipment_model IS 'Snapshot of the equipment model provided during service intake.';
COMMENT ON COLUMN public.service_tickets.serial_number IS 'Snapshot of the equipment serial number provided during service intake.';
COMMENT ON COLUMN public.service_tickets.institution IS 'Institution, clinic, or hospital where the service is requested.';
COMMENT ON COLUMN public.service_tickets.department IS 'Department or area where the equipment is located (e.g. Pediatria, Quirofano).';
COMMENT ON COLUMN public.service_tickets.equipment_operating IS 'Indicates whether the equipment is currently powering on / operating.';
COMMENT ON COLUMN public.service_tickets.failure_description IS 'Detailed description of the failure, malfunction, or specific service requirement.';
COMMENT ON COLUMN public.service_tickets.intake_details IS 'Flexible JSON structure for service-type-specific questions (preventivo, correctivo, diagnostico).';
