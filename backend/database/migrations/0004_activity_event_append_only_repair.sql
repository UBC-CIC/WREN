-- ===========================================================================
-- 0004_activity_event_append_only_repair.sql
--
-- Activity-log tamper-resistance remediation (INFORMATION_DISCLOSURE finding):
-- make public.activity_event append-only at the database layer and strip the
-- excess UPDATE/DELETE privilege from the wren_admin role.
--
-- WHY: activity_event is the platform's only record of "who did what" and,
-- unlike draft / resolution_status_history, was reachable for UPDATE/DELETE by
-- wren_admin -- the role the Admin Lambda (41 internet-reachable routes) runs
-- as. No application code issues UPDATE/DELETE against it, so the privilege was
-- pure excess: any code-execution / SQL-abuse defect could let an attacker
-- erase their own trail with no independent copy.
--
-- The append-only trigger and the REVOKE/GRANT split were folded into the
-- squashed baseline (0001), but a database that had already recorded
-- 0001_baseline.sql in schema_migrations does NOT re-run the rewritten file --
-- so environments provisioned before the fold-in still have a mutable/deletable
-- activity_event and an over-privileged wren_admin. Like 0002 and 0003, this is
-- a forward-only, idempotent repair that fixes existing environments and is a
-- harmless no-op on fresh deploys (which already received it from the baseline).
--
-- Every statement here is idempotent:
--   * CREATE OR REPLACE FUNCTION      -- re-defines in place
--   * DROP TRIGGER IF EXISTS + CREATE -- re-creates cleanly
--   * REVOKE                          -- no-op if the privilege isn't held
--   * GRANT                           -- idempotent in PostgreSQL
-- The role-existence guard keeps it safe even if the role was somehow not
-- created.
-- ===========================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'wren_admin') THEN
    RAISE EXCEPTION
      'Role wren_admin does not exist; run the role-creation baseline (0001) first.';
  END IF;
END $$;

-- 1. Append-only enforcement function (mirrors reject_draft_update /
--    reject_resolution_history_update): reject any UPDATE or DELETE.
CREATE OR REPLACE FUNCTION public.reject_activity_event_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'activity_event is append-only (id=%; operation=%).', OLD.id, TG_OP;
END;
$$;

-- 2. BEFORE UPDATE OR DELETE trigger enforcing append-only at the DB layer,
--    independent of any role's table privileges.
DROP TRIGGER IF EXISTS activity_event_append_only ON public.activity_event;
CREATE TRIGGER activity_event_append_only
  BEFORE UPDATE OR DELETE ON public.activity_event
  FOR EACH ROW EXECUTE FUNCTION public.reject_activity_event_mutation();

-- 3. Least-privilege: the Admin Lambda only ever appends and reads the trail.
--    Drop the excess UPDATE/DELETE and re-assert exactly SELECT, INSERT.
REVOKE UPDATE, DELETE ON TABLE public.activity_event FROM wren_admin;
GRANT SELECT, INSERT ON TABLE public.activity_event TO wren_admin;
