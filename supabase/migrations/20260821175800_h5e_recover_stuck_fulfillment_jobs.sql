CREATE OR REPLACE FUNCTION public.claim_next_fulfillment_job()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_job public.order_fulfillment_jobs%rowtype;
BEGIN
  SELECT *
  INTO v_job
  FROM public.order_fulfillment_jobs
  WHERE (
      (status IN ('pending', 'failed') AND next_attempt_at <= now())
      OR (status = 'processing' AND updated_at < now() - interval '10 minutes')
    )
    AND attempts < max_attempts
  ORDER BY next_attempt_at ASC, created_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  UPDATE public.order_fulfillment_jobs
  SET status = 'processing',
      attempts = attempts + 1,
      updated_at = now()
  WHERE id = v_job.id
  RETURNING * INTO v_job;

  RETURN jsonb_build_object(
    'job_id', v_job.id,
    'order_id', v_job.order_id,
    'attempts', v_job.attempts,
    'max_attempts', v_job.max_attempts
  );
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.claim_next_fulfillment_job() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_next_fulfillment_job() TO service_role;
