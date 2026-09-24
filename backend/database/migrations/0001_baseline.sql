-- 0001_baseline.sql
-- Consolidated idempotent schema baseline (migr 0001-0036).
-- Generated from pg_dump of deployed wren-dev database (2026-08-31).
-- Safe to run against an already-migrated database.

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', true);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: reject_draft_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.reject_draft_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.document_id IS DISTINCT FROM OLD.document_id
       OR NEW.version_number IS DISTINCT FROM OLD.version_number
       OR NEW.s3_key IS DISTINCT FROM OLD.s3_key
       OR NEW.segments IS DISTINCT FROM OLD.segments
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
        RAISE EXCEPTION
            'Draft rows are immutable (id=%); only content/word_count may be updated for autosave.',
            OLD.id;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: reject_resolution_history_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.reject_resolution_history_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'resolution_status_history is append-only (id=%).', OLD.id;
END;
$$;


--
-- Name: reject_activity_event_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.reject_activity_event_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'activity_event is append-only (id=%; operation=%).', OLD.id, TG_OP;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: access_grant; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.access_grant (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    granted_by uuid,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_at timestamp with time zone,
    document_type_id uuid NOT NULL
);


--
-- Name: activity_event; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.activity_event (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    actor_pseudonym text NOT NULL,
    verb text NOT NULL,
    object_type text NOT NULL,
    object_ref text NOT NULL,
    document_type_id uuid,
    department_id uuid,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    context jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: aggregate_counter; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.aggregate_counter (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    scope_kind text NOT NULL,
    scope_id uuid,
    metric text NOT NULL,
    window_start timestamp with time zone NOT NULL,
    value bigint DEFAULT 0 NOT NULL
);


--
-- Name: anchor; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.anchor (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    feedback_item_id uuid NOT NULL,
    draft_id uuid NOT NULL,
    paragraph_index integer NOT NULL,
    start_offset integer NOT NULL,
    end_offset integer NOT NULL,
    content_fingerprint text NOT NULL,
    state text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT anchor_end_offset_check CHECK ((end_offset >= 0)),
    CONSTRAINT anchor_offset_order CHECK ((end_offset >= start_offset)),
    CONSTRAINT anchor_paragraph_index_check CHECK ((paragraph_index >= 0)),
    CONSTRAINT anchor_start_offset_check CHECK ((start_offset >= 0)),
    CONSTRAINT anchor_state_check CHECK ((state = ANY (ARRAY['active'::text, 'removed'::text])))
);


--
-- Name: app_user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.app_user (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email text NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    idp_subject text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: content_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.content_type (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    document_type_id uuid NOT NULL,
    label text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: custom_metadata_field; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.custom_metadata_field (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    document_type_id uuid NOT NULL,
    label text NOT NULL,
    required boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: debrief_section_applicability; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.debrief_section_applicability (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    document_id uuid NOT NULL,
    draft_id uuid NOT NULL,
    error_category_id uuid NOT NULL,
    applicable boolean NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: department; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.department (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    prompt text,
    access_state text DEFAULT 'OPEN'::text NOT NULL,
    archived_at timestamp with time zone,
    visibility_state text DEFAULT 'VISIBLE'::text NOT NULL,
    ask_wren_prompt text,
    CONSTRAINT department_access_state_check CHECK ((access_state = ANY (ARRAY['OPEN'::text, 'LOCKED'::text]))),
    CONSTRAINT department_visibility_state_check CHECK ((visibility_state = ANY (ARRAY['VISIBLE'::text, 'PERMITTED_ONLY'::text])))
);


--
-- Name: department_visibility_grant; Type: TABLE; Schema: public; Owner: -
--
-- Explicit Department discovery permissions (never submission access). A grant
-- is active while revoked_at IS NULL; revocation is a soft-delete.

CREATE TABLE IF NOT EXISTS public.department_visibility_grant (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  department_id uuid NOT NULL,
  user_id uuid NOT NULL,
  granted_by uuid,
  granted_at timestamp with time zone DEFAULT now() NOT NULL,
  revoked_at timestamp with time zone,
  CONSTRAINT department_visibility_grant_revocation_check
    CHECK (revoked_at IS NULL OR revoked_at >= granted_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_department_visibility_grant_active
  ON public.department_visibility_grant (department_id, user_id)
  WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_department_visibility_grant_user_active
  ON public.department_visibility_grant (user_id, department_id)
  WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_department_visibility_grant_department_active
  ON public.department_visibility_grant (department_id, granted_at, id)
  WHERE revoked_at IS NULL;


--
-- Name: document; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.document (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_user_id uuid NOT NULL,
    document_type_id uuid NOT NULL,
    content_type_id uuid,
    name text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    status text DEFAULT 'Still Drafting'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    debrief_generation_count integer DEFAULT 0 NOT NULL,
    draft_create_count integer DEFAULT 0 NOT NULL,
    CONSTRAINT document_debrief_generation_count_check CHECK ((debrief_generation_count >= 0)),
    CONSTRAINT document_draft_create_count_check CHECK ((draft_create_count >= 0))
);


--
-- Name: document_ingest_job; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.document_ingest_job (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    document_id uuid NOT NULL,
    s3_key text NOT NULL,
    file_name text NOT NULL,
    status text NOT NULL,
    error_message text,
    draft_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    ocr_engine text DEFAULT 'textract'::text NOT NULL,
    comparison jsonb,
    CONSTRAINT document_ingest_job_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'processing'::text, 'completed'::text, 'failed'::text])))
);


--
-- Name: document_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.document_type (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    department_id uuid NOT NULL,
    name text NOT NULL,
    access_state text DEFAULT 'OPEN'::text NOT NULL,
    size_limit_words integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT document_type_access_state_check CHECK ((access_state = ANY (ARRAY['OPEN'::text, 'LOCKED'::text]))),
    CONSTRAINT writing_type_size_limit_words_check CHECK (((size_limit_words IS NULL) OR (size_limit_words > 0)))
);


--
-- Name: document_type_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.document_type_config (
    document_type_id uuid NOT NULL,
    tone text,
    density text,
    category_priority jsonb DEFAULT '[]'::jsonb NOT NULL,
    type_prompt_text text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    tone_description text,
    density_description text,
    structure_description text,
    restrictions_description text,
    notes_description text,
    citation_config jsonb
);


--
-- Name: draft; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.draft (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    document_id uuid NOT NULL,
    version_number integer NOT NULL,
    s3_key text NOT NULL,
    segments jsonb NOT NULL,
    word_count integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    content jsonb,
    content_updated_at timestamp with time zone,
    header jsonb,
    footer jsonb,
    ocr_confidence numeric(5,2),
    CONSTRAINT draft_version_number_check CHECK ((version_number > 0)),
    CONSTRAINT draft_word_count_check CHECK ((word_count >= 0))
);


--
-- Name: error_category; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.error_category (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    document_type_id uuid NOT NULL,
    name text NOT NULL,
    internal_guidance text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: feedback_helpfulness_rating; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.feedback_helpfulness_rating (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    document_id uuid NOT NULL,
    draft_id uuid,
    document_type_id uuid NOT NULL,
    helpful boolean NOT NULL,
    comment text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: feedback_item; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.feedback_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    document_id uuid NOT NULL,
    error_category_id uuid NOT NULL,
    kind text NOT NULL,
    question_text text NOT NULL,
    current_anchor_id uuid,
    citation_reference_id uuid,
    source_draft_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    quoted_text text,
    positive_note text,
    CONSTRAINT feedback_item_kind_check CHECK ((kind = ANY (ARRAY['inline'::text, 'structural'::text, 'strength'::text])))
);


--
-- Name: notification; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.notification (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    notification_type_id uuid NOT NULL,
    recipient_user_id uuid NOT NULL,
    state character varying(20) DEFAULT 'unread'::character varying NOT NULL,
    rendered_content text NOT NULL,
    action_url text,
    dedup_key character varying(512),
    context jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    read_at timestamp with time zone,
    dismissed_at timestamp with time zone,
    CONSTRAINT notification_state_check CHECK (((state)::text = ANY ((ARRAY['unread'::character varying, 'read'::character varying, 'dismissed'::character varying])::text[])))
);


--
-- Name: notification_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.notification_type (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug character varying(100) NOT NULL,
    label character varying(255) NOT NULL,
    display_template text NOT NULL,
    action_url_template text,
    target_roles jsonb DEFAULT '[]'::jsonb NOT NULL,
    dedup_strategy jsonb DEFAULT '{"enabled": false}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: override; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.override (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    document_type_id uuid NOT NULL,
    bounds jsonb NOT NULL,
    reason text NOT NULL,
    granted_by uuid,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: platform_usage_policy; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.platform_usage_policy (
    id integer DEFAULT 1 NOT NULL,
    message_limit integer DEFAULT 100 NOT NULL,
    debrief_generation_limit integer DEFAULT 15 NOT NULL,
    document_upload_limit integer DEFAULT 30 NOT NULL,
    drafts_per_document_limit integer DEFAULT 15 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    bedrock_model_id text,
    CONSTRAINT platform_usage_policy_debrief_generation_limit_check CHECK ((debrief_generation_limit >= 1)),
    CONSTRAINT platform_usage_policy_document_upload_limit_check CHECK ((document_upload_limit >= 1)),
    CONSTRAINT platform_usage_policy_drafts_per_document_limit_check CHECK ((drafts_per_document_limit >= 1)),
    CONSTRAINT platform_usage_policy_id_check CHECK ((id = 1)),
    CONSTRAINT platform_usage_policy_message_limit_check CHECK ((message_limit >= 1))
);


--
-- Name: reference_material; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.reference_material (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tier text NOT NULL,
    department_id uuid,
    document_type_id uuid,
    title text NOT NULL,
    section text,
    content_kind text NOT NULL,
    s3_key text,
    inline_content text,
    embedding_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT reference_material_content_kind_check CHECK ((content_kind = ANY (ARRAY['file'::text, 'text'::text, 'html'::text]))),
    CONSTRAINT reference_material_tier_check CHECK ((tier = ANY (ARRAY['org'::text, 'domain'::text]))),
    CONSTRAINT reference_material_tier_scope CHECK ((((tier = 'department'::text) AND (department_id IS NOT NULL)) OR ((tier = 'type'::text) AND (document_type_id IS NOT NULL))))
);


--
-- Name: resolution_status_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.resolution_status_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    feedback_item_id uuid NOT NULL,
    draft_id uuid NOT NULL,
    status text NOT NULL,
    evaluated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT resolution_status_history_status_check CHECK ((status = ANY (ARRAY['resolved'::text, 'partially_resolved'::text, 'still_unresolved'::text, 'removed'::text, 'unchanged'::text])))
);


--
-- Name: role_assignment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.role_assignment (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    role text NOT NULL,
    scope jsonb,
    granted_by uuid,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT role_assignment_role_check CHECK ((role = ANY (ARRAY['Student'::text, 'DepartmentAdmin'::text, 'TechnicalAdmin'::text])))
);



--
-- Name: topic; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.topic (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    department_id uuid NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: usage_counter; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.usage_counter (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    scope_kind text NOT NULL,
    scope_id uuid,
    period_start timestamp with time zone NOT NULL,
    consumed integer DEFAULT 0 NOT NULL,
    CONSTRAINT usage_counter_consumed_check CHECK ((consumed >= 0)),
    CONSTRAINT usage_counter_scope_kind_check CHECK ((scope_kind = ANY (ARRAY['platform'::text, 'documentType'::text])))
);


--
-- Name: usage_limit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.usage_limit (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    scope_kind text NOT NULL,
    scope_id uuid,
    limit_value integer NOT NULL,
    period text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT usage_limit_limit_value_check CHECK ((limit_value >= 0)),
    CONSTRAINT usage_limit_scope_kind_check CHECK ((scope_kind = ANY (ARRAY['platform'::text, 'documentType'::text])))
);


--
-- Name: user_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.user_identities (
    user_id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying(255) NOT NULL,
    cognito_subject character varying(500) NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: user_lifetime_usage; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.user_lifetime_usage (
    user_id uuid NOT NULL,
    document_upload_count integer DEFAULT 0 NOT NULL,
    CONSTRAINT user_lifetime_usage_document_upload_count_check CHECK ((document_upload_count >= 0))
);


--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.user_roles (
    user_role_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    role character varying(50) NOT NULL,
    scope_kind character varying(50),
    scope_id uuid,
    assigned_at timestamp without time zone DEFAULT now(),
    assigned_by uuid
);


--
-- Name: access_grant access_grant_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.access_grant
    ADD CONSTRAINT access_grant_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: activity_event activity_event_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.activity_event
    ADD CONSTRAINT activity_event_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: aggregate_counter aggregate_counter_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.aggregate_counter
    ADD CONSTRAINT aggregate_counter_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: aggregate_counter aggregate_counter_scope_kind_scope_id_metric_window_start_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.aggregate_counter
    ADD CONSTRAINT aggregate_counter_scope_kind_scope_id_metric_window_start_key UNIQUE (scope_kind, scope_id, metric, window_start);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: anchor anchor_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.anchor
    ADD CONSTRAINT anchor_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: app_user app_user_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.app_user
    ADD CONSTRAINT app_user_email_key UNIQUE (email);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: app_user app_user_idp_subject_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.app_user
    ADD CONSTRAINT app_user_idp_subject_key UNIQUE (idp_subject);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: app_user app_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.app_user
    ADD CONSTRAINT app_user_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: content_type content_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.content_type
    ADD CONSTRAINT content_type_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: custom_metadata_field custom_metadata_field_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.custom_metadata_field
    ADD CONSTRAINT custom_metadata_field_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: debrief_section_applicability debrief_section_applicability_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.debrief_section_applicability
    ADD CONSTRAINT debrief_section_applicability_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: document_ingest_job document_ingest_job_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.document_ingest_job
    ADD CONSTRAINT document_ingest_job_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: document document_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.document
    ADD CONSTRAINT document_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: draft draft_document_id_version_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.draft
    ADD CONSTRAINT draft_document_id_version_number_key UNIQUE (document_id, version_number);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: draft draft_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.draft
    ADD CONSTRAINT draft_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: error_category error_category_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.error_category
    ADD CONSTRAINT error_category_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: error_category error_category_writing_type_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.error_category
    ADD CONSTRAINT error_category_writing_type_id_name_key UNIQUE (document_type_id, name);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: feedback_helpfulness_rating feedback_helpfulness_rating_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.feedback_helpfulness_rating
    ADD CONSTRAINT feedback_helpfulness_rating_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: feedback_item feedback_item_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.feedback_item
    ADD CONSTRAINT feedback_item_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: notification notification_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: notification_type notification_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.notification_type
    ADD CONSTRAINT notification_type_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: notification_type notification_type_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.notification_type
    ADD CONSTRAINT notification_type_slug_key UNIQUE (slug);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: department organization_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.department
    ADD CONSTRAINT organization_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: override override_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.override
    ADD CONSTRAINT override_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: platform_usage_policy platform_usage_policy_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.platform_usage_policy
    ADD CONSTRAINT platform_usage_policy_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: reference_material reference_material_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.reference_material
    ADD CONSTRAINT reference_material_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: resolution_status_history resolution_status_history_feedback_item_id_draft_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.resolution_status_history
    ADD CONSTRAINT resolution_status_history_feedback_item_id_draft_id_key UNIQUE (feedback_item_id, draft_id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: resolution_status_history resolution_status_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.resolution_status_history
    ADD CONSTRAINT resolution_status_history_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: role_assignment role_assignment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.role_assignment
    ADD CONSTRAINT role_assignment_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;



--
-- Name: topic topic_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.topic
    ADD CONSTRAINT topic_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: feedback_helpfulness_rating uq_feedback_helpfulness_document_draft; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.feedback_helpfulness_rating
    ADD CONSTRAINT uq_feedback_helpfulness_document_draft UNIQUE (document_id, draft_id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: debrief_section_applicability uq_section_applicability; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.debrief_section_applicability
    ADD CONSTRAINT uq_section_applicability UNIQUE (document_id, draft_id, error_category_id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: usage_counter usage_counter_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.usage_counter
    ADD CONSTRAINT usage_counter_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: usage_counter usage_counter_scope_kind_scope_id_period_start_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.usage_counter
    ADD CONSTRAINT usage_counter_scope_kind_scope_id_period_start_key UNIQUE (scope_kind, scope_id, period_start);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: usage_limit usage_limit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.usage_limit
    ADD CONSTRAINT usage_limit_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: user_identities user_identities_cognito_subject_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.user_identities
    ADD CONSTRAINT user_identities_cognito_subject_key UNIQUE (cognito_subject);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: user_identities user_identities_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.user_identities
    ADD CONSTRAINT user_identities_email_key UNIQUE (email);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: user_identities user_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.user_identities
    ADD CONSTRAINT user_identities_pkey PRIMARY KEY (user_id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: user_lifetime_usage user_lifetime_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.user_lifetime_usage
    ADD CONSTRAINT user_lifetime_usage_pkey PRIMARY KEY (user_id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_role_id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: user_roles user_roles_user_id_role_scope_kind_scope_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_user_id_role_scope_kind_scope_id_key UNIQUE (user_id, role, scope_kind, scope_id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: document_type_config writing_type_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.document_type_config
    ADD CONSTRAINT writing_type_config_pkey PRIMARY KEY (document_type_id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: document_type writing_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.document_type
    ADD CONSTRAINT writing_type_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: idx_access_grant_document_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_access_grant_document_type ON public.access_grant USING btree (document_type_id);


--
-- Name: idx_access_grant_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_access_grant_user ON public.access_grant USING btree (user_id);


--
-- Name: idx_activity_event_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_activity_event_timestamp ON public.activity_event USING btree ("timestamp");


--
-- Name: idx_anchor_draft; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_anchor_draft ON public.anchor USING btree (draft_id);


--
-- Name: idx_anchor_feedback_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_anchor_feedback_item ON public.anchor USING btree (feedback_item_id);


--
-- Name: idx_content_type_document_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_content_type_document_type ON public.content_type USING btree (document_type_id);


--
-- Name: idx_custom_metadata_field_document_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_custom_metadata_field_document_type ON public.custom_metadata_field USING btree (document_type_id);


--
-- Name: idx_document_document_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_document_document_type ON public.document USING btree (document_type_id);


--
-- Name: idx_document_ingest_job_document; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_document_ingest_job_document ON public.document_ingest_job USING btree (document_id, created_at DESC);


--
-- Name: idx_document_ingest_job_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_document_ingest_job_status ON public.document_ingest_job USING btree (status) WHERE (status = ANY (ARRAY['queued'::text, 'processing'::text]));


--
-- Name: idx_document_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_document_owner ON public.document USING btree (owner_user_id);


--
-- Name: idx_document_type_dept; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_document_type_dept ON public.document_type USING btree (department_id);


--
-- Name: idx_draft_document; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_draft_document ON public.draft USING btree (document_id);


--
-- Name: idx_error_category_document_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_error_category_document_type ON public.error_category USING btree (document_type_id);


--
-- Name: idx_feedback_item_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_feedback_item_category ON public.feedback_item USING btree (error_category_id);


--
-- Name: idx_feedback_item_document; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_feedback_item_document ON public.feedback_item USING btree (document_id);


--
-- Name: idx_helpfulness_rating_document_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_helpfulness_rating_document_type ON public.feedback_helpfulness_rating USING btree (document_type_id, created_at DESC);


--
-- Name: idx_notification_dedup; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_dedup ON public.notification USING btree (dedup_key) WHERE ((dedup_key IS NOT NULL) AND ((state)::text <> 'dismissed'::text));


--
-- Name: idx_notification_inbox; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_notification_inbox ON public.notification USING btree (recipient_user_id, created_at DESC) WHERE ((state)::text <> 'dismissed'::text);


--
-- Name: idx_notification_type_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_notification_type_slug ON public.notification_type USING btree (slug);


--
-- Name: idx_notification_unread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_notification_unread ON public.notification USING btree (recipient_user_id) WHERE ((state)::text = 'unread'::text);


--
-- Name: idx_override_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_override_user ON public.override USING btree (user_id);


--
-- Name: idx_reference_material_dept; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_reference_material_dept ON public.reference_material USING btree (department_id);


--
-- Name: idx_reference_material_document_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_reference_material_document_type ON public.reference_material USING btree (document_type_id);


--
-- Name: idx_resolution_history_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_resolution_history_item ON public.resolution_status_history USING btree (feedback_item_id);


--
-- Name: idx_role_assignment_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_role_assignment_user ON public.role_assignment USING btree (user_id);


--
-- Name: idx_section_applicability_debrief; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_section_applicability_debrief ON public.debrief_section_applicability USING btree (document_id, draft_id);


--
-- Name: idx_topic_dept; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_topic_dept ON public.topic USING btree (department_id);


--
-- Name: idx_user_identities_cognito_subject; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_user_identities_cognito_subject ON public.user_identities USING btree (cognito_subject);


--
-- Name: idx_user_roles_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_user_roles_role ON public.user_roles USING btree (role);


--
-- Name: idx_user_roles_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON public.user_roles USING btree (user_id);


--
-- Name: draft draft_immutable; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS draft_immutable ON public.draft;
CREATE TRIGGER draft_immutable BEFORE UPDATE ON public.draft FOR EACH ROW EXECUTE FUNCTION public.reject_draft_update();


--
-- Name: resolution_status_history resolution_status_history_append_only; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS resolution_status_history_append_only ON public.resolution_status_history;
CREATE TRIGGER resolution_status_history_append_only BEFORE UPDATE ON public.resolution_status_history FOR EACH ROW EXECUTE FUNCTION public.reject_resolution_history_update();


--
-- Name: activity_event activity_event_append_only; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS activity_event_append_only ON public.activity_event;
CREATE TRIGGER activity_event_append_only BEFORE UPDATE OR DELETE ON public.activity_event FOR EACH ROW EXECUTE FUNCTION public.reject_activity_event_mutation();


--
-- Name: access_grant access_grant_granted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.access_grant
    ADD CONSTRAINT access_grant_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.app_user(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: access_grant access_grant_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.access_grant
    ADD CONSTRAINT access_grant_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: activity_event activity_event_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.activity_event
    ADD CONSTRAINT activity_event_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.department(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: activity_event activity_event_document_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.activity_event
    ADD CONSTRAINT activity_event_document_type_id_fkey FOREIGN KEY (document_type_id) REFERENCES public.document_type(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: anchor anchor_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.anchor
    ADD CONSTRAINT anchor_draft_id_fkey FOREIGN KEY (draft_id) REFERENCES public.draft(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: anchor anchor_feedback_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.anchor
    ADD CONSTRAINT anchor_feedback_item_id_fkey FOREIGN KEY (feedback_item_id) REFERENCES public.feedback_item(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: content_type content_type_writing_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.content_type
    ADD CONSTRAINT content_type_writing_type_id_fkey FOREIGN KEY (document_type_id) REFERENCES public.document_type(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: custom_metadata_field custom_metadata_field_writing_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.custom_metadata_field
    ADD CONSTRAINT custom_metadata_field_writing_type_id_fkey FOREIGN KEY (document_type_id) REFERENCES public.document_type(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: debrief_section_applicability debrief_section_applicability_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.debrief_section_applicability
    ADD CONSTRAINT debrief_section_applicability_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.document(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: debrief_section_applicability debrief_section_applicability_error_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.debrief_section_applicability
    ADD CONSTRAINT debrief_section_applicability_error_category_id_fkey FOREIGN KEY (error_category_id) REFERENCES public.error_category(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: document document_content_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.document
    ADD CONSTRAINT document_content_type_id_fkey FOREIGN KEY (content_type_id) REFERENCES public.content_type(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: document_ingest_job document_ingest_job_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.document_ingest_job
    ADD CONSTRAINT document_ingest_job_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.document(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: document_ingest_job document_ingest_job_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.document_ingest_job
    ADD CONSTRAINT document_ingest_job_draft_id_fkey FOREIGN KEY (draft_id) REFERENCES public.draft(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: document document_owner_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.document
    ADD CONSTRAINT document_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: document document_writing_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.document
    ADD CONSTRAINT document_writing_type_id_fkey FOREIGN KEY (document_type_id) REFERENCES public.document_type(id) ON DELETE RESTRICT;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: draft draft_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.draft
    ADD CONSTRAINT draft_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.document(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: error_category error_category_writing_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.error_category
    ADD CONSTRAINT error_category_writing_type_id_fkey FOREIGN KEY (document_type_id) REFERENCES public.document_type(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: feedback_helpfulness_rating feedback_helpfulness_rating_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.feedback_helpfulness_rating
    ADD CONSTRAINT feedback_helpfulness_rating_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.document(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: feedback_helpfulness_rating feedback_helpfulness_rating_document_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.feedback_helpfulness_rating
    ADD CONSTRAINT feedback_helpfulness_rating_document_type_id_fkey FOREIGN KEY (document_type_id) REFERENCES public.document_type(id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: feedback_item feedback_item_citation_reference_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.feedback_item
    ADD CONSTRAINT feedback_item_citation_reference_id_fkey FOREIGN KEY (citation_reference_id) REFERENCES public.reference_material(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: feedback_item feedback_item_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.feedback_item
    ADD CONSTRAINT feedback_item_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.document(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: feedback_item feedback_item_error_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.feedback_item
    ADD CONSTRAINT feedback_item_error_category_id_fkey FOREIGN KEY (error_category_id) REFERENCES public.error_category(id) ON DELETE RESTRICT;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: feedback_item feedback_item_source_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.feedback_item
    ADD CONSTRAINT feedback_item_source_draft_id_fkey FOREIGN KEY (source_draft_id) REFERENCES public.draft(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: access_grant fk_access_grant_document_type; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.access_grant
    ADD CONSTRAINT fk_access_grant_document_type FOREIGN KEY (document_type_id) REFERENCES public.document_type(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: feedback_item fk_feedback_item_current_anchor; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.feedback_item
    ADD CONSTRAINT fk_feedback_item_current_anchor FOREIGN KEY (current_anchor_id) REFERENCES public.anchor(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: notification notification_notification_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_notification_type_id_fkey FOREIGN KEY (notification_type_id) REFERENCES public.notification_type(id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: notification notification_recipient_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_recipient_user_id_fkey FOREIGN KEY (recipient_user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: override override_granted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.override
    ADD CONSTRAINT override_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.app_user(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: override override_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.override
    ADD CONSTRAINT override_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: override override_writing_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.override
    ADD CONSTRAINT override_writing_type_id_fkey FOREIGN KEY (document_type_id) REFERENCES public.document_type(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: reference_material reference_material_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.reference_material
    ADD CONSTRAINT reference_material_organization_id_fkey FOREIGN KEY (department_id) REFERENCES public.department(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: reference_material reference_material_writing_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.reference_material
    ADD CONSTRAINT reference_material_writing_type_id_fkey FOREIGN KEY (document_type_id) REFERENCES public.document_type(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: resolution_status_history resolution_status_history_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.resolution_status_history
    ADD CONSTRAINT resolution_status_history_draft_id_fkey FOREIGN KEY (draft_id) REFERENCES public.draft(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: resolution_status_history resolution_status_history_feedback_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.resolution_status_history
    ADD CONSTRAINT resolution_status_history_feedback_item_id_fkey FOREIGN KEY (feedback_item_id) REFERENCES public.feedback_item(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: role_assignment role_assignment_granted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.role_assignment
    ADD CONSTRAINT role_assignment_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.app_user(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: role_assignment role_assignment_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.role_assignment
    ADD CONSTRAINT role_assignment_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: department_visibility_grant FK constraints; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.department_visibility_grant
    ADD CONSTRAINT department_visibility_grant_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.department(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
ALTER TABLE ONLY public.department_visibility_grant
    ADD CONSTRAINT department_visibility_grant_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;

DO $$ BEGIN
ALTER TABLE ONLY public.department_visibility_grant
    ADD CONSTRAINT department_visibility_grant_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.app_user(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: topic topic_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.topic
    ADD CONSTRAINT topic_organization_id_fkey FOREIGN KEY (department_id) REFERENCES public.department(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: user_lifetime_usage user_lifetime_usage_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.user_lifetime_usage
    ADD CONSTRAINT user_lifetime_usage_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_user(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: user_roles user_roles_assigned_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES public.user_identities(user_id);
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_identities(user_id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: document_type_config writing_type_config_writing_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.document_type_config
    ADD CONSTRAINT writing_type_config_writing_type_id_fkey FOREIGN KEY (document_type_id) REFERENCES public.document_type(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;


--
-- Name: document_type writing_type_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $$ BEGIN
ALTER TABLE ONLY public.document_type
    ADD CONSTRAINT writing_type_organization_id_fkey FOREIGN KEY (department_id) REFERENCES public.department(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;
END $$;

-- ===========================================================================
-- ROLES (from 0027_app_db_roles.sql)
-- ===========================================================================

DO $$ BEGIN
  CREATE ROLE wren_authorizer LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE ROLE wren_appsync_auth LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE ROLE wren_document LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE ROLE wren_admin LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE ROLE wren_audit LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE ROLE wren_feedback_orch LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE ROLE wren_feedback_engine LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE ROLE wren_notification LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

GRANT CONNECT ON DATABASE appdb TO
  wren_authorizer, wren_appsync_auth, wren_document, wren_admin,
  wren_audit, wren_feedback_orch, wren_feedback_engine, wren_notification;

GRANT USAGE ON SCHEMA public TO
  wren_authorizer, wren_appsync_auth, wren_document, wren_admin,
  wren_audit, wren_feedback_orch, wren_feedback_engine, wren_notification;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO
  wren_authorizer, wren_appsync_auth, wren_document, wren_admin,
  wren_audit, wren_feedback_orch, wren_feedback_engine, wren_notification;

-- wren_authorizer
-- UPDATE on app_user is required for first-login provisioning: ensureAppUser
-- runs `INSERT ... ON CONFLICT (idp_subject) DO UPDATE` plus an email-relink
-- UPDATE, and PostgreSQL requires UPDATE privilege to plan the ON CONFLICT DO
-- UPDATE even when no conflict fires.
GRANT SELECT, INSERT, UPDATE ON TABLE public.app_user TO wren_authorizer;
GRANT SELECT, INSERT ON TABLE public.role_assignment TO wren_authorizer;
GRANT SELECT ON TABLE public.access_grant TO wren_authorizer;

-- wren_appsync_auth
GRANT SELECT ON TABLE public.app_user, public.role_assignment, public.access_grant, public.document TO wren_appsync_auth;

-- wren_document
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  public.document, public.draft, public.feedback_item, public.anchor,
  public.resolution_status_history, public.document_ingest_job, public.aggregate_counter
  TO wren_document;
GRANT SELECT ON TABLE public.document_type, public.department, public.content_type TO wren_document;
GRANT SELECT ON TABLE public.platform_usage_policy TO wren_document;
GRANT SELECT ON TABLE public.access_grant TO wren_document;
GRANT SELECT ON TABLE public.custom_metadata_field TO wren_document;

-- wren_admin
REVOKE UPDATE, DELETE ON TABLE
  public.activity_event
  FROM wren_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  public.department, public.document_type, public.document_type_config,
  public.error_category, public.content_type, public.custom_metadata_field,
  public.topic, public.reference_material, public.app_user, public.role_assignment,
  public.access_grant, public.usage_limit, public.usage_counter,
  public.override, public.platform_usage_policy, public.aggregate_counter
  TO wren_admin;
GRANT SELECT, INSERT ON TABLE public.activity_event
  TO wren_admin;
GRANT SELECT ON TABLE
  public.document, public.draft, public.feedback_item, public.anchor,
  public.resolution_status_history, public.feedback_helpfulness_rating,
  public.debrief_section_applicability
  TO wren_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.department_visibility_grant
  TO wren_admin;

-- wren_audit
GRANT SELECT ON TABLE
  public.aggregate_counter, public.document_type, public.department,
  public.resolution_status_history, public.feedback_item, public.error_category,
  public.feedback_helpfulness_rating, public.debrief_section_applicability
  TO wren_audit;

-- wren_feedback_orch
GRANT SELECT ON TABLE
  public.document, public.draft, public.feedback_item, public.anchor,
  public.error_category, public.document_type, public.document_type_config,
  public.department, public.resolution_status_history, public.platform_usage_policy
  TO wren_feedback_orch;
GRANT SELECT, INSERT, UPDATE ON TABLE
  public.feedback_helpfulness_rating, public.debrief_section_applicability
  TO wren_feedback_orch;
GRANT UPDATE ON TABLE public.document TO wren_feedback_orch;

-- wren_feedback_engine
GRANT SELECT ON TABLE
  public.document, public.draft, public.document_type, public.document_type_config,
  public.department, public.error_category, public.platform_usage_policy,
  public.feedback_item, public.anchor
  TO wren_feedback_engine;
GRANT SELECT, INSERT, UPDATE ON TABLE
  public.feedback_item, public.anchor, public.resolution_status_history,
  public.aggregate_counter
  TO wren_feedback_engine;
GRANT DELETE ON TABLE
  public.feedback_item, public.anchor, public.resolution_status_history
  TO wren_feedback_engine;

-- wren_notification
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.notification, public.notification_type
  TO wren_notification;
GRANT SELECT ON TABLE
  public.role_assignment, public.override, public.document_type,
  public.app_user, public.department
  TO wren_notification;

-- ===========================================================================
-- SEED DATA
-- ===========================================================================

-- platform_usage_policy — single required row
INSERT INTO public.platform_usage_policy (id, message_limit, debrief_generation_limit, document_upload_limit, drafts_per_document_limit)
VALUES (1, 100, 15, 30, 15)
ON CONFLICT (id) DO NOTHING;

-- notification_type catalog (from 0024_notification_type_seed.sql)
INSERT INTO public.notification_type (slug, label, display_template, action_url_template, target_roles, dedup_strategy)
VALUES
  ('ai-debrief-ready', 'AI Debrief ready', 'Your feedback for "{{documentName}}" is ready to review.', '/documents/{{documentId}}/debrief', '["Student"]', '{"enabled": false}'),
  ('ai-debrief-failed', 'AI Debrief failed', 'Feedback generation for "{{documentName}}" encountered an issue. You can retry.', '/documents/{{documentId}}', '["Student"]', '{"enabled": true, "windowMinutes": 5, "keyFields": ["documentId", "draftId"]}'),
  ('access-grant-approved', 'Access grant approved', 'Your access request for {{documentTypeName}} has been approved.', '/documents', '["Student"]', '{"enabled": false}'),
  ('access-grant-denied', 'Access grant denied', 'Your access request for {{documentTypeName}} was not approved.', NULL, '["Student"]', '{"enabled": false}'),
  ('usage-limit-warning', 'Usage limit warning', 'You''re approaching the usage limit for {{scopeName}}.', NULL, '["Student"]', '{"enabled": true, "windowMinutes": 1440, "keyFields": ["scopeName"]}'),
  ('usage-limit-reached', 'Usage limit reached', 'You''ve reached the usage limit for {{scopeName}}.', NULL, '["Student"]', '{"enabled": true, "windowMinutes": 1440, "keyFields": ["scopeName"]}'),
  ('temporary-override-granted', 'Temporary override granted', 'You''ve been granted additional usage for {{documentTypeName}}.', '/documents', '["Student"]', '{"enabled": false}'),
  ('access-request-pending', 'Access request pending', '{{studentName}} has requested access to {{documentTypeName}}.', '/admin/access-requests', '["DepartmentAdmin"]', '{"enabled": false}'),
  ('usage-limit-reached-doctype', 'Usage limit reached (Doc Type)', '{{documentTypeName}} has reached its usage limit.', '/admin/usage', '["DepartmentAdmin"]', '{"enabled": true, "windowMinutes": 1440, "keyFields": ["documentTypeId"]}'),
  ('guardrail-violation-flagged', 'Guardrail violation flagged', 'A guardrail violation was flagged for {{documentTypeName}}.', '/admin/guardrails', '["DepartmentAdmin"]', '{"enabled": true, "windowMinutes": 60, "keyFields": ["documentTypeId"]}'),
  ('new-department-appointment', 'New Department appointment', 'You''ve been appointed to administer {{departmentName}}.', '/admin/dashboard', '["DepartmentAdmin"]', '{"enabled": false}'),
  ('reference-material-failed', 'Reference material processing failed', 'Reference material "{{materialTitle}}" for {{documentTypeName}} failed to process.', '/admin/reference-materials', '["DepartmentAdmin"]', '{"enabled": false}'),
  ('override-expiring', 'Override expiring', 'An override you granted for {{studentName}} in {{documentTypeName}} expires soon.', '/admin/overrides', '["DepartmentAdmin"]', '{"enabled": true, "windowMinutes": 720, "keyFields": ["overrideId"]}'),
  ('override-expired', 'Override expired', 'An override you granted for {{studentName}} in {{documentTypeName}} has expired.', '/admin/overrides', '["DepartmentAdmin"]', '{"enabled": true, "windowMinutes": 1440, "keyFields": ["overrideId"]}'),
  ('usage-limit-reached-platform', 'Usage limit reached (platform)', 'The platform-wide usage limit has been reached.', '/admin/platform/usage', '["TechnicalAdmin"]', '{"enabled": true, "windowMinutes": 1440, "keyFields": []}'),
  ('feedback-job-failures', 'Feedback job failures', 'DLQ depth has exceeded the configured threshold ({{count}} messages).', '/admin/platform/jobs', '["TechnicalAdmin"]', '{"enabled": true, "windowMinutes": 60, "keyFields": []}'),
  ('guardrail-violation-spike', 'Guardrail violation spike', 'Guardrail rejection rate has exceeded the anomaly threshold.', '/admin/platform/guardrails', '["TechnicalAdmin"]', '{"enabled": true, "windowMinutes": 60, "keyFields": []}'),
  ('role-assignment-confirmation', 'Role assignment confirmation', 'You assigned {{targetRole}} to {{targetUserName}}.', '/admin/users', '["TechnicalAdmin"]', '{"enabled": false}'),
  ('model-config-change-confirmation', 'Model/config change confirmation', 'You updated {{configField}}.', '/admin/platform/config', '["TechnicalAdmin"]', '{"enabled": false}')
ON CONFLICT (slug) DO NOTHING;

-- smoke-test reference data (from 0004_seed_reference_data.sql)
INSERT INTO public.department (id, name)
VALUES ('550e8400-e29b-41d4-a716-446655440000'::uuid, 'Test Department')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.document_type (id, department_id, name, access_state)
VALUES ('550e8400-e29b-41d4-a716-446655440001'::uuid, '550e8400-e29b-41d4-a716-446655440000'::uuid, 'Contract', 'OPEN')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.document_type_config (document_type_id, tone, density, type_prompt_text)
VALUES ('550e8400-e29b-41d4-a716-446655440001'::uuid, 'professional', 'medium', 'Review this contract for clarity and completeness.')
ON CONFLICT (document_type_id) DO NOTHING;

INSERT INTO public.content_type (id, document_type_id, label)
VALUES ('550e8400-e29b-41d4-a716-446655440002'::uuid, '550e8400-e29b-41d4-a716-446655440001'::uuid, 'Standard')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.custom_metadata_field (id, document_type_id, label, required)
VALUES ('550e8400-e29b-41d4-a716-446655440003'::uuid, '550e8400-e29b-41d4-a716-446655440001'::uuid, 'Party Name', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.error_category (id, document_type_id, name)
VALUES ('550e8400-e29b-41d4-a716-446655440004'::uuid, '550e8400-e29b-41d4-a716-446655440001'::uuid, 'Ambiguity')
ON CONFLICT (id) DO NOTHING;
-- ===========================================================================
-- SEED DATA: Law example department (extracted from the reference deployment)
--
-- A worked example domain so a fresh deployment ships with a usable Law
-- department: its department-level prompt, five document types, each type's
-- feedback error categories, and each type's configuration (per-category
-- definitions/criteria, restrictions, and notes).
--
-- Fixed UUIDs + ON CONFLICT DO NOTHING make this idempotent and
-- non-destructive: it only inserts on a database that does not already have
-- these rows, and never overwrites edits an administrator makes later.
-- Insert order respects foreign keys: department -> document_type ->
-- error_category -> document_type_config (config JSON references category ids).
-- ===========================================================================

INSERT INTO public.department (id, name, prompt, ask_wren_prompt, access_state, visibility_state)
VALUES (
  '6ed1a3f1-45e6-4f5d-b1fd-b020b3193b22'::uuid,
  'Law',
  '[Department Context]
Students at the UBC Peter A. Allard School of Law. Writers range from incoming students with limited writing experience to upper-year students in advanced legal research and writing courses. The tool supports the pedagogical principle that "writing is thinking" helping students develop clear, disciplined legal writing skills through practice and AI-guided feedback rather than AI-generated text.

[Writing Standards]
Canadian Guide to Uniform Legal Citation (McGill Guide). IRAC structure (Issue, Rule, Application, Conclusion) for analytical writing. Pinpoint citations required for all propositions of law. Document conventions vary by document type: court factums, client memoranda, legal briefs, and professional communications each follow distinct formatting rules.

[Restricted Topics]
Do not comment on the merits or correctness of legal arguments. Do not suggest, recommend, or cite specific case law, legislation, or secondary sources. Do not assess whether a statutory interpretation or application of precedent is substantively correct. Do not provide replacement prose or rewritten text: the tool must guide, not ghostwrite. Focus only on writing quality: clarity of expression, logical structure, citation format compliance, persuasive technique, and coherence of argument.',
  NULL,
  'OPEN',
  'VISIBLE'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.document_type (id, department_id, name, access_state, size_limit_words)
VALUES
  ('2786bdbe-9769-4db4-b7ea-39ad6d1b1f93'::uuid, '6ed1a3f1-45e6-4f5d-b1fd-b020b3193b22'::uuid, 'Appellate Factum', 'OPEN', NULL),
  ('8641d4d9-314a-49ee-a91a-2ec91595b7d3'::uuid, '6ed1a3f1-45e6-4f5d-b1fd-b020b3193b22'::uuid, 'Case Brief', 'OPEN', NULL),
  ('21b80f9f-1c07-4f86-8f88-2f30b91627f0'::uuid, '6ed1a3f1-45e6-4f5d-b1fd-b020b3193b22'::uuid, 'Legal Memorandum', 'OPEN', NULL),
  ('84e34997-d8df-4299-8602-21d8b7600652'::uuid, '6ed1a3f1-45e6-4f5d-b1fd-b020b3193b22'::uuid, 'Opinion Letters', 'OPEN', NULL),
  ('4228bd25-50a5-4e00-b4d2-254ece835af8'::uuid, '6ed1a3f1-45e6-4f5d-b1fd-b020b3193b22'::uuid, 'Pleadings', 'OPEN', NULL)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.error_category (id, document_type_id, name, internal_guidance)
VALUES
  ('97314e88-38cf-4e44-ac47-49c8bbf6971e'::uuid, '21b80f9f-1c07-4f86-8f88-2f30b91627f0'::uuid, 'Clarity', NULL),
  ('878da013-04d9-402c-84cb-134132b13b26'::uuid, '21b80f9f-1c07-4f86-8f88-2f30b91627f0'::uuid, 'Consistency/Coherence', NULL),
  ('5b9211c4-0109-4fea-88e0-276cce16bc61'::uuid, '21b80f9f-1c07-4f86-8f88-2f30b91627f0'::uuid, 'Objectivity/Neutrality', NULL),
  ('99e50a8d-6841-432c-8a8d-1b4791c856d2'::uuid, '21b80f9f-1c07-4f86-8f88-2f30b91627f0'::uuid, 'Organization', NULL),
  ('fd77f903-71bb-4804-aaec-a50ccc8acb6d'::uuid, '21b80f9f-1c07-4f86-8f88-2f30b91627f0'::uuid, 'Persuasiveness', NULL),
  ('16cc03dc-ae71-4448-a226-793f4b462621'::uuid, '21b80f9f-1c07-4f86-8f88-2f30b91627f0'::uuid, 'Spelling/Grammar', NULL),
  ('c22080cc-4f06-4301-87e6-0d8a5561bab6'::uuid, '21b80f9f-1c07-4f86-8f88-2f30b91627f0'::uuid, 'Tone', NULL),
  ('46c62dff-c345-4f59-a1bd-aafcbe69b9e7'::uuid, '2786bdbe-9769-4db4-b7ea-39ad6d1b1f93'::uuid, 'Clarity', NULL),
  ('fd7dffb6-5848-4e42-b77f-bf5f5712f102'::uuid, '2786bdbe-9769-4db4-b7ea-39ad6d1b1f93'::uuid, 'Consistency / Coherence', NULL),
  ('5a76032a-8096-4ada-98d2-09ab5d81daaf'::uuid, '2786bdbe-9769-4db4-b7ea-39ad6d1b1f93'::uuid, 'Objectivity / Neutrality', NULL),
  ('e0854532-b531-4240-8e8b-8c0be3cb1d60'::uuid, '2786bdbe-9769-4db4-b7ea-39ad6d1b1f93'::uuid, 'Organisation', NULL),
  ('37bfecb1-6108-483b-9b82-3bbd01448110'::uuid, '2786bdbe-9769-4db4-b7ea-39ad6d1b1f93'::uuid, 'Persuasiveness', NULL),
  ('0966155f-8f19-4f6c-ae1e-2dfd95e67fa7'::uuid, '2786bdbe-9769-4db4-b7ea-39ad6d1b1f93'::uuid, 'Spelling / Grammar', NULL),
  ('c9fa4fc1-e07e-4813-9363-8f018e95dd60'::uuid, '2786bdbe-9769-4db4-b7ea-39ad6d1b1f93'::uuid, 'Tone', NULL),
  ('0510a34c-cd69-4206-876b-390f350d52c9'::uuid, '4228bd25-50a5-4e00-b4d2-254ece835af8'::uuid, 'Clarity', NULL),
  ('7cf28a6b-9faa-4874-a0f9-944b55c38bd7'::uuid, '4228bd25-50a5-4e00-b4d2-254ece835af8'::uuid, 'Consistency / Coherence', NULL),
  ('fb20a89e-f315-48fa-ba0f-303bf183953e'::uuid, '4228bd25-50a5-4e00-b4d2-254ece835af8'::uuid, 'Objectivity / Neutrality', NULL),
  ('17b21503-cec7-4ee0-ac05-755efe526894'::uuid, '4228bd25-50a5-4e00-b4d2-254ece835af8'::uuid, 'Organisation', NULL),
  ('a55035e7-5711-449f-aacd-980284e1344b'::uuid, '4228bd25-50a5-4e00-b4d2-254ece835af8'::uuid, 'Persuasiveness', NULL),
  ('340be16d-a674-42e0-9993-2ef521e8dabd'::uuid, '4228bd25-50a5-4e00-b4d2-254ece835af8'::uuid, 'Spelling / Grammar', NULL),
  ('63392164-31e4-4777-9098-23ef1a306938'::uuid, '4228bd25-50a5-4e00-b4d2-254ece835af8'::uuid, 'Tone', NULL),
  ('d5c49dbc-3d2a-4026-9d92-16c70ea34cc7'::uuid, '84e34997-d8df-4299-8602-21d8b7600652'::uuid, 'Clarity', NULL),
  ('04659fb5-64f9-4ff3-989d-80e0721ae1db'::uuid, '84e34997-d8df-4299-8602-21d8b7600652'::uuid, 'Consistency / Coherence', NULL),
  ('11b35fc4-1616-4ff8-bdce-0719995d45df'::uuid, '84e34997-d8df-4299-8602-21d8b7600652'::uuid, 'Objectivity / Neutrality', NULL),
  ('08a11314-171f-4a92-98ba-9be1fc5f24ad'::uuid, '84e34997-d8df-4299-8602-21d8b7600652'::uuid, 'Organisation', NULL),
  ('ca33ffc7-c664-4a99-b3be-b9042db4d88e'::uuid, '84e34997-d8df-4299-8602-21d8b7600652'::uuid, 'Persuasiveness', NULL),
  ('fabfd612-6e0b-49d1-9806-1c8d03ad6159'::uuid, '84e34997-d8df-4299-8602-21d8b7600652'::uuid, 'Spelling / Grammar', NULL),
  ('5d69afc8-d108-45d3-b164-624830120d3d'::uuid, '84e34997-d8df-4299-8602-21d8b7600652'::uuid, 'Tone', NULL),
  ('80bb7a87-c01e-4226-b694-d87f75bff115'::uuid, '8641d4d9-314a-49ee-a91a-2ec91595b7d3'::uuid, 'Clarity', NULL),
  ('7e43ec78-6478-4a26-b24d-39963c406d92'::uuid, '8641d4d9-314a-49ee-a91a-2ec91595b7d3'::uuid, 'Consistency / Coherence', NULL),
  ('713550d1-f147-428d-ac29-af17a59095de'::uuid, '8641d4d9-314a-49ee-a91a-2ec91595b7d3'::uuid, 'Objectivity / Neutrality', NULL),
  ('a3c1b8af-1fc5-4b16-b8ed-344723dc8d19'::uuid, '8641d4d9-314a-49ee-a91a-2ec91595b7d3'::uuid, 'Organisation', NULL),
  ('fcc3bab5-4748-49eb-af89-761f46f01cb0'::uuid, '8641d4d9-314a-49ee-a91a-2ec91595b7d3'::uuid, 'Persuasiveness', NULL),
  ('bd108c0c-1602-4ccc-a37d-e9d71cd7f20c'::uuid, '8641d4d9-314a-49ee-a91a-2ec91595b7d3'::uuid, 'Spelling / Grammar', NULL),
  ('67a276c3-0584-42a0-a36b-17028f596a9c'::uuid, '8641d4d9-314a-49ee-a91a-2ec91595b7d3'::uuid, 'Tone', NULL)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.document_type_config (
  document_type_id, tone, density, category_priority, type_prompt_text,
  tone_description, density_description, structure_description,
  restrictions_description, notes_description, citation_config
) VALUES (
  '8641d4d9-314a-49ee-a91a-2ec91595b7d3'::uuid,
  NULL,
  NULL,
  '["80bb7a87-c01e-4226-b694-d87f75bff115","7e43ec78-6478-4a26-b24d-39963c406d92","713550d1-f147-428d-ac29-af17a59095de","a3c1b8af-1fc5-4b16-b8ed-344723dc8d19","bd108c0c-1602-4ccc-a37d-e9d71cd7f20c","67a276c3-0584-42a0-a36b-17028f596a9c"]'::jsonb,
  'Identify the primary purpose of this case brief. Determine whether the document effectively summarizes the judicial decision by accurately presenting the facts, legal issues, applicable rules, courtâ€™s reasoning, and final holding in a concise and accessible manner.',
  NULL,
  '{"v":1,"overrides":{"80bb7a87-c01e-4226-b694-d87f75bff115":{"definition":"Evaluate whether the case brief presents legal facts, issues, reasoning, and outcomes in a way that is easy to understand. Determine whether legal concepts are explained clearly, sentences are concise, and readers can follow the case without unnecessary ambiguity or confusion. ","criteria":"Assess whether every section communicates its purpose clearly, avoids vague or overly complex wording, defines legal terminology where necessary, and enables a reader unfamiliar with the case to understand the facts, legal issues, court''s reasoning, and decision without difficulty. "},"7e43ec78-6478-4a26-b24d-39963c406d92":{"definition":"Evaluate whether the case brief maintains logical organization and consistent presentation throughout. Determine whether the facts, legal issues, analysis, and conclusion are connected smoothly and whether terminology, formatting, and references remain consistent.","criteria":"Assess whether the brief follows a logical progression from facts to issues, rule, analysis, and conclusion; uses consistent legal terminology and formatting; avoids contradictions; and ensures each section supports the overall narrative without repetition or abrupt transitions. "},"713550d1-f147-428d-ac29-af17a59095de":{"definition":"Evaluate whether the case brief summarizes the court''s decision impartially by presenting the facts, legal arguments, judicial reasoning, and outcome without personal opinions, bias, or persuasive language.","criteria":"Assess whether the brief accurately represents both parties'' positions, faithfully reflects the court''s reasoning, avoids subjective or emotionally charged language, and distinguishes factual statements from legal analysis without introducing unsupported interpretations. "},"a3c1b8af-1fc5-4b16-b8ed-344723dc8d19":{"definition":"Since a case brief is a summary of a case, it should be organized in a way that is easy to digest and references legal concepts. Briefing cases should also help the reader understand these legal concepts. ","criteria":"The student should start with a citation that provides the name of the case (e.g. Ignatius v Bell [1913] 2 FMSLR 115), followed by a description of the nature of the case that lays out why there is a legal action before the court, the nature of that action, and what remedy is being sought (e.g. the plaintiff sued for specific performance due to breach of an agreement). After the nature of the case, the facts relevant to the legal issues should be brought up in 3-5 sentences. Next, the legal issue should be stated in the form of a question (e.g. is the acceptance of the offer complete upon posting?). The key to identifying issues in a case is to reflect upon who wants what, and if they succeeded or failed in getting it. Following the legal issue, the student should provide a statement of the general principle of law that the case illustrates (e.g. in cases of acceptance through post, acceptance is complete upon posting). Finally, the student should explain why and how the court applied the general rule of law to the facts of the case in the holding or decision section. The student should finish with a statement indicating how the case was finally decided (e.g. the judgement was entered for defendant due to the reason of negligence by the plaintiff even though the option was accepted on 16 August.)","frameworkKey":"custom"},"bd108c0c-1602-4ccc-a37d-e9d71cd7f20c":{"definition":"Evaluate whether the case brief uses correct spelling, grammar, punctuation, capitalization, and sentence structure while maintaining professional legal writing conventions. ","criteria":"Assess whether the document is free from spelling mistakes, grammatical errors, punctuation issues, typographical errors, and awkward sentence construction. Verify that citations, legal terminology, and proper names are used accurately and consistently. "},"67a276c3-0584-42a0-a36b-17028f596a9c":{"definition":"Evaluate whether the case brief maintains a professional, formal, and academic legal tone appropriate for summarizing a judicial decision.","criteria":"Assess whether the writing remains objective, respectful, precise, and professional throughout, avoids conversational or persuasive language, and reflects the seriousness and neutrality expected in legal case briefs while accurately conveying the court''s reasoning and decision. "}}}',
  '',
  'Review the case brief for common legal writing mistakes, including omission of key facts or legal issues, inaccurate statements of the holding, misrepresentation of the court''s reasoning, unsupported conclusions, excessive detail, repetition, or poor organization. 

Identify any sections that contain factual inaccuracies, misleading summaries, unsupported assumptions, or missing legal context. Ensure the brief reflects the court''s decision faithfully without adding interpretation beyond what is supported by the judgment. 

Check whether the document avoids common structural issues such as mixing facts with analysis, presenting issues out of sequence, inconsistent terminology, unnecessary quotations, or failing to clearly distinguish between the parties'' arguments and the court''s reasoning.',
  'Determine whether additional legal background would improve the reader''s understanding of the case. Suggest brief contextual information, such as relevant legal principles, procedural posture, governing legislation, or significant precedent, without overwhelming the summary. 

Evaluate whether the case brief provides sufficient procedural background to explain how the dispute reached the court and why the legal issues were before the judge. Identify any missing procedural details that would help readers understand the decision. 

Assess whether readers unfamiliar with the legal subject matter would benefit from concise explanations of legal terminology, doctrines, or procedural rules referenced in the case. Recommend additional context only where it improves comprehension without reducing the brevity of the case brief. 

Review whether the case brief includes enough contextual information to understand the significance of the court''s decision, including the relationship between the parties, the nature of the dispute, the applicable legal framework, and the broader implications of the ruling, while maintaining an objective and concise summary. ',
  NULL
)
ON CONFLICT (document_type_id) DO NOTHING;

INSERT INTO public.document_type_config (
  document_type_id, tone, density, category_priority, type_prompt_text,
  tone_description, density_description, structure_description,
  restrictions_description, notes_description, citation_config
) VALUES (
  '2786bdbe-9769-4db4-b7ea-39ad6d1b1f93'::uuid,
  NULL,
  NULL,
  '["46c62dff-c345-4f59-a1bd-aafcbe69b9e7","fd7dffb6-5848-4e42-b77f-bf5f5712f102","e0854532-b531-4240-8e8b-8c0be3cb1d60","37bfecb1-6108-483b-9b82-3bbd01448110","0966155f-8f19-4f6c-ae1e-2dfd95e67fa7","c9fa4fc1-e07e-4813-9363-8f018e95dd60"]'::jsonb,
  'Appellate factums are formal written legal arguments submitted to an appellate court, consisting of a statement of facts, the issues on appeal, and a structured legal argument with a list of authorities. They guide judges on why a lower court decision should be changed or upheld.',
  NULL,
  '{"v":1,"overrides":{"46c62dff-c345-4f59-a1bd-aafcbe69b9e7":{"definition":"The factum presents the issues, facts, and arguments in clear, concise, and understandable language. Headings and subheadings guide the reader through the analysis.","criteria":"Use headings to organize the argument. Write in plain language where possible. Avoid unnecessary repetition, legal jargon without explanation, and overly long sentences. The reader should be able to easily identify the issues, arguments, and requested relief."},"fd7dffb6-5848-4e42-b77f-bf5f5712f102":{"definition":"The factum advances a consistent theory of the case and maintains logical connections between the facts, issues, standards of review, and legal arguments.","criteria":"Arguments should be internally consistent and logically developed. Facts relied upon in the argument should align with those presented in the statement of facts. Legal authorities should support, rather than contradict, the position being advanced."},"37bfecb1-6108-483b-9b82-3bbd01448110":{"definition":"The factum effectively persuades the appellate court that the appeal should be allowed or dismissed based on the applicable law and record.","criteria":"The statement of facts should not include any argument. However, the selected facts should support the legal position advanced in the argument section. Arguments should clearly explain why the lower court erred (for appellants) or why the decision should be upheld (for respondents), using legal authority, careful reasoning, and references to the record."},"e0854532-b531-4240-8e8b-8c0be3cb1d60":{"definition":"The factum follows the required appellate format and presents information in a logical sequence.","criteria":"A factum must contain:\nA title page\nA table of contents\nStatement of facts\nStart with a basic statement of the finding of the court below\nThen use short clear sentences that summarize the relevant factual findings \nDo not repeat all of the facts in the trial decision\nDo not include any argument here\nErrors in Judgement (for appellate factum)\nArgument\nSet out your position, referring to the facts and law you rely on, in an organized, logical and persuasive way\nAppellants should explain where/why the trial judge came to the wrong conclusions\nNature of order sought \nâ€œThe appellant seeks an Order that the appeal be allowed and a new trial ordered.â€","frameworkKey":"custom"},"0966155f-8f19-4f6c-ae1e-2dfd95e67fa7":{"definition":"The factum demonstrates professional writing and adherence to legal citation conventions.","criteria":"Correct spelling, grammar, punctuation, and citation form (e.g., Bluebook, McGill Guide, or applicable local citation rules). Writing errors should be minimal or absent, as such errors undermine credibility and readability."},"c9fa4fc1-e07e-4813-9363-8f018e95dd60":{"definition":"The factum maintains a professional, respectful, and objective advocacy style appropriate for an appellate court.","criteria":"Use a formal and respectful tone. Avoid emotional language, personal attacks, exaggeration, or inflammatory statements. Criticize the reasoning of the lower court, not the judge personally. Advocacy should be measured, evidence-based, and focused on legal analysis."}}}',
  '',
  'The factum must not contain irrelevant material, reproduce material contained in the appeal record or transcript, and exceed 30 pages.
Avoid aggressive or insulting language about the opposing partyâ€™s arguments. Avoid language that is too casual or colloquial, or that is unnecessarily flowery or legalistic. Avoid stating the obvious.',
  'A good factum is succinct. It should be a clear, tightly written summary of the argument. Short sentences are almost always more effective than long ones. Breaking up long sentences helps the reader follow along.',
  NULL
)
ON CONFLICT (document_type_id) DO NOTHING;

INSERT INTO public.document_type_config (
  document_type_id, tone, density, category_priority, type_prompt_text,
  tone_description, density_description, structure_description,
  restrictions_description, notes_description, citation_config
) VALUES (
  '21b80f9f-1c07-4f86-8f88-2f30b91627f0'::uuid,
  NULL,
  NULL,
  '["97314e88-38cf-4e44-ac47-49c8bbf6971e","878da013-04d9-402c-84cb-134132b13b26","5b9211c4-0109-4fea-88e0-276cce16bc61","99e50a8d-6841-432c-8a8d-1b4791c856d2","16cc03dc-ae71-4448-a226-793f4b462621","c22080cc-4f06-4301-87e6-0d8a5561bab6"]'::jsonb,
  'A memo of law is a succinct document that provides an opinion on the state of the law surrounding a particular legal issue. Memos function as a reference tool for lawyers.',
  'Memos of law are drafted by articling students or junior lawyers for more senior lawyers to get an idea of what the law says. If the memo is intended to be shared with a client, the student should avoid legal jargon.  The tone should be impartial and balanced, the language should be moderately formal, and the writing should be clear and concise. The student should use the active voice and avoid contractions and the use of first-person.',
  '{"v":1,"overrides":{"99e50a8d-6841-432c-8a8d-1b4791c856d2":{"definition":"The typical legal memo structure is defined as IRAC or FILAC or FIBLAC. IRAC begins with a statement of the legal question (Issue), identification of the governing law (Rule), application of that law to the specific facts (Application), and conclusion with the likely outcome (Conclusion). \nFILAC structure begins with a Facts section, outlining the particular client''s facts relevant to the legal issue. The Issue is then stated in the form of a question or questions. The Law section sets out the law, drawn from legislation (where applicable) and case law, relevant to answering the legal Issue(s). The Analysis section applies the law, as described in the Law section, to the client''s facts, as outlined in the Facts section, for the purpose of providing an answer to each legal Issue. The conclusion briefly states the ultimate conclusions to each Issue reached in the Analysis section. \nFIBLAC structure is FILAC, but incorporating a Brief Answer after the Issues section, so the reader can quickly see how the writer will be answering each of the questions identified in the Issues section. \nOther variations include FIRAC, ILAC, etc.","criteria":"A strong memo clearly signals each part of the IRAC/FILAC/FIBLAC, etc., structure through the use of headings. \n\nFacts: contains only facts relevant to the Issues outlined in the Issues section. May be organised chronologically or in another logical manner. No law should be discussed in this section, and the Facts should be presented objectively. \n\nIssue/Issues: Framed narrowly and precisely, incorporating the key legal question and the most relevant facts (often in a \"whether... when...\" construction), rather than a vague restatement of the general area of law. May be framed such that the Issues can be answered in a Yes/No manner.\n\nRule/Law: Stated in full before any application begins, synthesized from all relevant authority (statutes, regulations, case law) rather than a single case, and organized from general rule to any exceptions or sub-rules, in the order the Application/Analysis will apply them.\n\nApplication/Analysis: Applies the law/legal rule(s) element-by-element (or factor-by-factor) directly to the client''s facts, explicitly connecting each fact to the corresponding legal standard, using analogous and distinguishable case comparisons rather than abstract restatement of the rule. Counterarguments are addressed within the Application/Analysis rather than ignored or relegated to an afterthought.\n\nConclusion: Directly answers the Issue as framed, states a calibrated prediction of outcome (not just \"yes\" or \"no\"), and does not introduce new rules, facts, or arguments not already addressed in the Application.\n\nStructural discipline: Typically, each issue in a multi-issue memo is a self-contained IRAC/FILAC unit; the memo does not skip stages, merge Rule and Application, or present Application material before the Rule has been fully stated. Sub-issues are nested clearly (e.g., mini-IRACs within a larger issue) without breaking the overall flow. In some cases, often for more straightforward legal issues, Law and Analysis (or Rule and Application) may be merged into a single section, but the purpose must remain to both clearly explain what the law (legislation/case law) says, and apply it to the client''s facts using comparator cases.","frameworkKey":"custom"},"97314e88-38cf-4e44-ac47-49c8bbf6971e":{"definition":"The degree to which legal analysis is expressed in plain, precise language so that a reader (often a supervising attorney under time pressure) can grasp the issue, the governing rule, and the reasoning on a single read, without needing to re-parse sentences or guess at antecedents.","criteria":"A strong memo uses short-to-medium sentences, defines terms of art on first use, avoids stacked qualifiers and nested clauses, and states legal conclusions before elaborating on them. Ambiguous pronouns, undefined abbreviations, and vague statutory paraphrases are absent. Case citations support specific propositions rather than vague general ones."},"878da013-04d9-402c-84cb-134132b13b26":{"definition":"Whether terminology, party references, case names, and the logical thread of the argument remain stable and internally consistent throughout the memorandum, so that no section contradicts or duplicates another.","criteria":"A strong memo uses the same defined terms and party labels throughout (e.g., consistently calling a party \"Employer\" rather than switching to \"the Company\" or \"Defendant\" without explanation), applies the same rule articulated in the Law section during the Analysis section without silently modifying it, and reaches a Conclusion that follows logically from the Analysus rather than introducing new reasoning."},"5b9211c4-0109-4fea-88e0-276cce16bc61":{"definition":"The degree to which the analysis presents both favorable and unfavorable authority and arguments fairly, reflecting a genuine prediction of outcome rather than one-sided advocacy â€” this is a defining feature that distinguishes a memo from a brief.","criteria":"A strong memo candidly identifies counterarguments and weaknesses in the client''s position, cites unfavorable authority where it exists, and assigns a realistic (not optimistic) likelihood of success. It does not omit adverse case law or frame facts in a one-sided way. Hedged, calibrated language (\"likely,\" \"a court would probably find\") is used appropriately rather than absolute claims."},"16cc03dc-ae71-4448-a226-793f4b462621":{"definition":"Correct spelling, grammar, punctuation, and citation form (e.g., McGill Guide or Canadian Open Access Legal Citation Guide (https://www.canlii.org/en/commentary/doc/2024CanLIIDocs830#!fragment//BQCwhgziBcwMYgK4DsDWszIQewE4BUBTADwBdoByCgSgBpltTCIBFRQ3AT0otokLC4EbDtyp8BQkAGU8pAELcASgFEAMioBqAQQByAYRW1SYAEbRS2ONWpA), since errors undermine credibility in a professional legal document.","criteria":"A strong memo has zero spelling or grammatical errors, uses correct legal citation format consistently, properly italicizes case names and signals, and follows consistent capitalization conventions for defined terms (e.g., \"Plaintiff,\" \"the Agreement\")."},"c22080cc-4f06-4301-87e6-0d8a5561bab6":{"definition":"A formal, professional, dispassionate register appropriate for internal legal communication â€” analytical and measured rather than argumentative, emotional, or colloquial. Objective analysis of the legal issue, not advocating for a particular outcome.","criteria":"A strong memo maintains a consistently formal, third-person, analytical voice throughout, avoids contractions, slang, or emotionally charged language, and conveys authority through precision and well-supported reasoning rather than assertive rhetoric."}}}',
  'The student should begin with a question at the top of the document, followed by the facts, the issues, and a brief answer. In the analysis, the student should start by using the issues and sub-issues as headings, and then state the applicable legal rules, and apply the rules to the facts. Finally, the student should provide a conclusion that elaborates on the brief answer section of the document and answers the question at the top of the document.',
  'The student should avoid simply summarizing cases chronologically rather than applying the law to the clientâ€™s specific facts. The student should not ignore counterarguments or bury their conclusion, leaving the reader guessing as to how the law applies to the question presented.

Excessive wordiness and legal jargon should be avoided as well. Ensure the student does not use the passive voice or have run-on sentences.',
  'Jurisdiction matters. A memo that applies the wrong state''s law or conflates federal and state standards is fundamentally unreliable regardless of its analytical quality. Students should identify the controlling jurisdiction in the Question Presented and apply only that jurisdiction''s authority throughout.

Case parentheticals are encouraged in the Discussion when a case is first introduced, summarizing the key facts and holding in one clause. This helps the reader evaluate whether the precedent is on point.

The Brief Answer is not a summary of the Discussion â€” it should be written so that a reader who reads nothing else understands both the answer and why. If the Brief Answer requires reading the Discussion to make sense, it needs revision.',
  NULL
)
ON CONFLICT (document_type_id) DO NOTHING;

INSERT INTO public.document_type_config (
  document_type_id, tone, density, category_priority, type_prompt_text,
  tone_description, density_description, structure_description,
  restrictions_description, notes_description, citation_config
) VALUES (
  '84e34997-d8df-4299-8602-21d8b7600652'::uuid,
  NULL,
  NULL,
  '["d5c49dbc-3d2a-4026-9d92-16c70ea34cc7","04659fb5-64f9-4ff3-989d-80e0721ae1db","11b35fc4-1616-4ff8-bdce-0719995d45df","08a11314-171f-4a92-98ba-9be1fc5f24ad","fabfd612-6e0b-49d1-9806-1c8d03ad6159","5d69afc8-d108-45d3-b164-624830120d3d"]'::jsonb,
  'The purpose of an opinion letter is to provide a legal opinion regarding specific matters arising from a transaction, document, or legal issue. The opinion identifies the scope of review, assumptions, qualifications, and applicable law, and communicates counselâ€™s legal conclusions in a clear and reliable manner for the benefit of the addressee.',
  NULL,
  '{"v":1,"overrides":{"d5c49dbc-3d2a-4026-9d92-16c70ea34cc7":{"definition":"The opinion letter clearly communicates the legal opinions being provided, including their scope, assumptions, qualifications, and conclusions.","criteria":"The letter uses precise and unambiguous language. The reader can easily identify the documents reviewed, applicable law, assumptions, and legal conclusions. Legal opinions are clearly distinguished from factual assumptions and qualifications."},"04659fb5-64f9-4ff3-989d-80e0721ae1db":{"definition":"The opinion letter presents a logically consistent legal analysis throughout the document.","criteria":"The scope of review, assumptions, qualifications, and legal opinions are aligned and do not contradict one another. Conclusions logically follow from the facts, investigations, and assumptions described in the letter."},"11b35fc4-1616-4ff8-bdce-0719995d45df":{"definition":"The opinion letter provides well-supported legal conclusions that inspire confidence in the reliability of the opinion.","criteria":"Each opinion is supported by the review conducted and the applicable legal framework. The analysis demonstrates sound legal reasoning and appropriate reliance on corporate records, certificates, documents, and governing law."},"08a11314-171f-4a92-98ba-9be1fc5f24ad":{"definition":"The opinion letter is structured in a logical and professional manner.","criteria":"The document follows a clear progression, typically including: introduction, documents reviewed, scope of review, applicable law, assumptions, opinions, qualifications, and reliance provisions. Headings and numbering facilitate easy reference.","frameworkKey":"custom"},"fabfd612-6e0b-49d1-9806-1c8d03ad6159":{"definition":"The opinion letter uses professional legal writing that is free from language and formatting errors.","criteria":"The document demonstrates correct grammar, spelling, punctuation, defined-term usage, and citation style. Any legal or corporate terminology is used consistently throughout the letter."},"5d69afc8-d108-45d3-b164-624830120d3d":{"definition":"The opinion letter maintains a professional, objective, and appropriately qualified tone.","criteria":"The letter provides legal conclusions confidently but without advocacy. The tone remains measured, neutral, and professional, avoiding speculation, argument, or overstating the certainty of legal conclusions. Appropriate assumptions, qualifications, and reliance limitations are included where necessary."}}}',
  '',
  'Failing to clearly define the scope of the opinion
Providing opinions outside of the lawyerâ€™s jurisdiction or expertise
Omitting assumptions qualifications, or limitations on reliance
Failing to identify the documents reviewed 
Presenting conclusions without sufficient legal analysis 
Expressing opinions on factual matters that have not been independently verified
Using ambiguous language that creates uncertainty regarding the opinion being given
Failing to specify the governing law applicable to the opinion',
  'Opinion letters are generally transactional documents that provide legal assurances to a client or third party regarding specific legal questions. They commonly include sections describing the documents reviewed, scope of review, investigations conducted, assumptions relied upon, applicable law, legal opinions, and limitations on reliance. The opinions expressed should be supported by the review undertaken and should be carefully confined to the matters expressly addressed in the letter.',
  NULL
)
ON CONFLICT (document_type_id) DO NOTHING;

INSERT INTO public.document_type_config (
  document_type_id, tone, density, category_priority, type_prompt_text,
  tone_description, density_description, structure_description,
  restrictions_description, notes_description, citation_config
) VALUES (
  '4228bd25-50a5-4e00-b4d2-254ece835af8'::uuid,
  NULL,
  NULL,
  '["0510a34c-cd69-4206-876b-390f350d52c9","7cf28a6b-9faa-4874-a0f9-944b55c38bd7","fb20a89e-f315-48fa-ba0f-303bf183953e","17b21503-cec7-4ee0-ac05-755efe526894","340be16d-a674-42e0-9993-2ef521e8dabd","63392164-31e4-4777-9098-23ef1a306938"]'::jsonb,
  'The purpose of a pleading is to clearly define the issues in dispute by setting out the material facts, legal basis, and relief sought. A pleading establishes the foundation of the litigation and identifies the case that the opposing party must answer. Material facts should be pleaded in a manner that supports the remedies sought while remaining distinct from evidence, argument, and opinion',
  NULL,
  '{"v":1,"overrides":{"0510a34c-cd69-4206-876b-390f350d52c9":{"definition":"The pleading clearly states the material facts, legal claims defenses, and relief sought.","criteria":"Facts are stated precisely and concisely. Allegations are easy to understand and distinguish from evidence, opinion, and legal argument. A reader should be able to quickly identify what happened, who was involved, and why relief is being sought."},"7cf28a6b-9faa-4874-a0f9-944b55c38bd7":{"definition":"The pleading presents a coherent factual and legal narrative without contradictions or unexplained inconsistencies.","criteria":"The facts, legal basis, and remedies sought support one another and do not contain contradictions. The pleading advances a logical narrative that explains how the alleged facts give rise to the claimed relief. Dates, amounts, parties, and material allegations remain consistent throughout the document."},"fb20a89e-f315-48fa-ba0f-303bf183953e":{"definition":"The pleading presents a factually grounded and legally supportable theory of the case.","criteria":"Material facts are selected and organized to support the legal claims or defenses being advanced. The pleading demonstrates that the requested relief follows logically from the facts alleged. Relevant remedies, including alternative remedies where appropriate, are clearly identified and supported by the pleaded facts."},"17b21503-cec7-4ee0-ac05-755efe526894":{"definition":"The pleading is structured in a logical and procedurally appropriate manner. ","criteria":"The document follows the required pleading structure and clearly separates the Statement of Facts, Relief Sought, and Legal Basis. Facts are presented in a logical sequence, generally chronological where appropriate. Headings, paragraph numbering, and defined terms are used effectively to improve readability.","frameworkKey":"custom"},"340be16d-a674-42e0-9993-2ef521e8dabd":{"definition":"The pleading uses correct grammar, spelling, punctuation, and legal terminology.","criteria":"The document should be free from typographical, grammatical, and formatting errors that could detract from its professionalism, credibility, or clarity."},"63392164-31e4-4777-9098-23ef1a306938":{"definition":"The pleading maintains a professional, objective, and respectful advocacy style appropriate for court filings.","criteria":"Arguments and allegations should be presented professionally and without unnecessary rhetoric, personal attacks, or emotional language. The tone should be persuasive while remaining consistent with the lawyerâ€™s duty of candour and professionalism before the Court."}}}',
  '',
  'Pleading evidence instead of material facts. 
Including personal opinions, speculation, argument, or commentary in the Statement of Facts. 
Failing to plead all facts necessary to support the relief sought. 
Omitting facts necessary to establish damages, loss, default, breach, limitation periods, or other elements of the claim.
Including irrelevant factual details that do not advance a recognized cause of action or defense. 
Failing to identify all available remedies or alternative forms of relief. 
Failing to connect the pleaded facts to the legal basis relied upon.
Leaving court form instructions, drafting notes, or template language in the final document. 
Failing to verify party names, corporate status, or other foundational information before commencing the action.',
  'Effective pleadings focus on material facts and present them in a logical sequence. Facts should be organized so that the reader can understand the parties, the relevant agreement or relationship, the events giving rise to the dispute, the alleged breach or wrongdoing, the resulting loss, and the remedies sought. The Legal Basis should be concise and tied directly to the pleaded facts. Where alternative legal remedies are available, consideration should be given to pleading them in the alternative.',
  NULL
)
ON CONFLICT (document_type_id) DO NOTHING;


-- ===========================================================================
-- SCHEMA ADDITIONS (from 0035_max_upload_file_size.sql, 0036_max_word_count.sql)
-- ===========================================================================

ALTER TABLE public.platform_usage_policy
    ADD COLUMN IF NOT EXISTS max_upload_file_size_bytes bigint NOT NULL DEFAULT 31457280
        CHECK (max_upload_file_size_bytes >= 1048576 AND max_upload_file_size_bytes <= 1073741824);

ALTER TABLE public.platform_usage_policy
    ADD COLUMN IF NOT EXISTS max_word_count integer NOT NULL DEFAULT 10000
        CHECK (max_word_count >= 100 AND max_word_count <= 100000);
