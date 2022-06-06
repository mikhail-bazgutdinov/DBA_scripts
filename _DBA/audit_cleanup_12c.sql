
./emctl setproperty agent -name SSLCipherSuites -value  TLS_RSA_WITH_AES_128_CBC_SHA:TLS_RSA_WITH_AES_256_CBC_SHA:RSA_WITH_AES_256_CBC_SHA256
./emctl stop agent
./emctl start agent

select * from aud$

SELECT * FROM audit_unified_policies

select * from AUDIT_UNIFIED_ENABLED_POLICIES;

select * from unified_audit_trail
  
select min(event_timestamp) from unified_audit_trail;
--All audit policies

SELECT decode(count(*),5,'true','false') FROM (
select decode(count(*),4,'true','false') "CHECK" from audit_unified_enabled_policies where policy_name in ( 'OBJ_POLICY_PCIDSS','SYSPRIV_POLICY_PCIDSS','STMT_POLICY_PCIDSS','DATAPUMP_POLICY_PCIDSS')
union all
select decode(count(*),1,'true','false') from dba_scheduler_jobs where owner||'.'||job_name in ('SYS.DAILY_OPERATIONS') and job_action like '%auddba.daily_audit_mgmt%' and state = 'SCHEDULED'
union all
select decode(count(*),0,'true','false') from audit_unified_enabled_policies where policy_name in (  'ORA_ACCOUNT_MGMT', 'ORA_CIS_RECOMMENDATIONS', 'ORA_DATABASE_PARAMETER', 'ORA_LOGON_FAILURES', 'ORA_RAS_POLICY_MGMT', 'ORA_RAS_SESSION_MGMT', 'ORA_SECURECONFIG')
union all
select decode(sum(i),0,'true','false') from (select count(*) i from dba_stmt_audit_opts
  union     select count(*)     from dba_priv_audit_opts
  union select count(*) from dba_obj_audit_opts)
union all 
select decode(count(*),2,'true','false') from dba_objects where owner = 'SYS' and objeCT_name = 'AUDDBA' and status = 'VALID') A
WHERE A."CHECK" = 'true';


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
