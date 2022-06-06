select * from aud$

SELECT * FROM audit_unified_policies

select * from AUDIT_UNIFIED_ENABLED_POLICIES;

select * from unified_audit_trail
  
select min(event_timestamp) from unified_audit_trail;

SELECT * FROM dba_audit_mgmt_last_arch_ts;


exec DBMS_AUDIT_MGMT.SET_LAST_ARCHIVE_TIMESTAMP (AUDIT_TRAIL_TYPE => DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED, LAST_ARCHIVE_TIME => SYSTIMESTAMP-4);

exec  DBMS_AUDIT_MGMT.INIT_CLEANUP( AUDIT_TRAIL_TYPE => DBMS_AUDIT_MGMT.AUDIT_TRAIL_ALL, DEFAULT_CLEANUP_INTERVAL => 12 );

exec DBMS_AUDIT_MGMT.CREATE_PURGE_JOB( audit_trail_type =>  DBMS_AUDIT_MGMT.AUDIT_TRAIL_ALL, audit_trail_purge_interval   =>12,  audit_trail_purge_name       =>  'AUDIT_TRAIL_PJ',  use_last_arch_timestamp      =>  TRUE);
exec DBMS_SCHEDULER.SET_ATTRIBUTE (   name => 'AUDIT_TRAIL_PJ',   attribute      => 'job_action',   value   =>'DBMS_AUDIT_MGMT.SET_LAST_ARCHIVE_TIMESTAMP (AUDIT_TRAIL_TYPE => DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED, LAST_ARCHIVE_TIME => SYSTIMESTAMP-4);'||chr(10)||'DBMS_AUDIT_MGMT.CLEAN_AUDIT_TRAIL(15, TRUE, 1);  ');


select * from dba_scheduler_jobs where JOB_NAME='AUDIT_TRAIL_PJ'


exec  DBMS_SCHEDULER.RUN_JOB(JOB_NAME => 'AUDIT_TRAIL_PJ',USE_CURRENT_SESSION => FALSE);


select * from dba_scheduler_job_run_details
where JOB_NAME='AUDIT_TRAIL_PJ'
order by ACTUAL_START_DATE desc
