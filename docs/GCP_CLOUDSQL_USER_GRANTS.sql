-- 수동 복구용 fallback.
-- GitOps의 GKE db-bootstrap Job이 배포되면 정상 흐름에서는 실행하지 않는다.
-- Cloud SQL Studio에서 accountsdb와 ledgerdb를 각각 선택해 한 번씩 실행한다.
-- dms_writer는 필수다. accounts_app/ledger_app은 존재할 때만 권한을 부여한다.

DO $block$
BEGIN
  IF current_database() NOT IN ('accountsdb', 'ledgerdb') THEN
    RAISE EXCEPTION 'accountsdb 또는 ledgerdb에서 실행하세요. 현재 DB: %', current_database();
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dms_writer') THEN
    RAISE EXCEPTION 'dms_writer 사용자가 없습니다. GCP 콘솔에서 먼저 생성하세요.';
  END IF;
END
$block$;

-- AfterConnectScript=SET session_replication_role=replica 실행에 필요하다.
GRANT cloudsqlsuperuser TO dms_writer;

DO $block$
DECLARE
  app_role text := CASE current_database()
    WHEN 'accountsdb' THEN 'accounts_app'
    WHEN 'ledgerdb' THEN 'ledger_app'
  END;
BEGIN
  EXECUTE format(
    'GRANT CONNECT, CREATE ON DATABASE %I TO dms_writer',
    current_database()
  );

  IF EXISTS (SELECT FROM pg_roles WHERE rolname = app_role) THEN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), app_role);
    EXECUTE format('GRANT USAGE ON SCHEMA public TO %I', app_role);
    EXECUTE format(
      'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO %I',
      app_role
    );
    EXECUTE format(
      'GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO %I',
      app_role
    );
    EXECUTE format(
      'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I',
      app_role
    );
    EXECUTE format(
      'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO %I',
      app_role
    );
  ELSE
    RAISE NOTICE '% 사용자가 없어 앱 권한은 건너뜁니다.', app_role;
  END IF;
END
$block$;

GRANT USAGE, CREATE ON SCHEMA public TO dms_writer;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
  ON ALL TABLES IN SCHEMA public TO dms_writer;
GRANT USAGE, SELECT, UPDATE
  ON ALL SEQUENCES IN SCHEMA public TO dms_writer;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLES TO dms_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO dms_writer;

SELECT
  current_database() AS database_name,
  pg_has_role('dms_writer', 'cloudsqlsuperuser', 'member') AS dms_cloudsqlsuperuser,
  has_database_privilege('dms_writer', current_database(), 'CREATE') AS dms_database_create,
  has_schema_privilege('dms_writer', 'public', 'CREATE') AS dms_schema_create;
