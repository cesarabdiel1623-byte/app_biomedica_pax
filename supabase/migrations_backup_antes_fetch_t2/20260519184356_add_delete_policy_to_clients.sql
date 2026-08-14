CREATE POLICY clients_delete_staff ON public.clients
FOR DELETE
TO public
USING (is_staff_or_admin());;
