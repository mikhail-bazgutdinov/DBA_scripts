alter session set nls_date_format='dd.mm.yyyy hh24:mi:ss';
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = ', ';
--SQL stats historical
select --ss.snaP_id,
--ss.dbid,
--min(sn.end_interval_Time) "First noticed"
--,max(sn.end_interval_Time) "Last noticed"
cast(trunc(sn.end_interval_Time,'hh24') as date) "EndDate/time"
,Round((to_date(to_char(max(sn.end_interval_Time),'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss')-to_date(to_char(min(sn.begin_interval_Time),'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss'))*24,1) "Duration,hours"
--,ss.sql_Id
--,count(distinct ss.sql_id) "SQL_ID"
,plan_hash_value
--,Round(sum(elapsed_time_delta)/1000,2) "Elapsed time, msec"
,decode(sum(executions_delta),0,cast(null as number),sum(executions_delta)) "Executions"
,Round(sum(executions_delta)/(to_date(to_char(max(sn.end_interval_Time),'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss')-to_date(to_char(min(sn.begin_interval_Time),'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss'))/24/3600,2) "Execs per sec"
,Round(sum(executions_delta)/(to_date(to_char(max(sn.end_interval_Time),'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss')-to_date(to_char(min(sn.begin_interval_Time),'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss'))/24,2) "Execs per hour"
,Round(sum(elapsed_time_delta)/1000000/decode(sum(executions_delta),0,1,sum(executions_delta)),2) "Elapsed sec per exec"
,Round(sum(elapsed_time_delta)/1000000/(to_date(to_char(max(sn.end_interval_Time),'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss')-to_date(to_char(min(sn.begin_interval_Time),'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss'))/24/3600,2) "Elapsed sec/sec (active sess)"
,Round(sum(rows_processed_delta)/(to_date(to_char(max(sn.end_interval_Time),'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss')-to_date(to_char(min(sn.begin_interval_Time),'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss'))/24/3600,2) "Rows per sec"
,Round(sum(cpu_time_delta)/1000/decode(sum(executions_delta),0,1,sum(executions_delta)),2) "CPU msec per exec"
,Round(sum(IOWAIT_delta)/1000/decode(sum(executions_delta),0,1,sum(executions_delta)),2) "IO wait msec per exec"
,Round(sum(CLWait_delta)/1000/decode(sum(executions_delta),0,1,sum(executions_delta)),2) "Cluster wait msec per exec"
,Round(sum(ApWait_delta)/1000/decode(sum(executions_delta),0,1,sum(executions_delta)),2) "Application wait msec per exec"
,Round(sum(CCWait_delta)/1000/decode(sum(executions_delta),0,1,sum(executions_delta)),2) "Concurrency wait msec per exec"
,Round(sum(PLSEXEC_TIME_delta)/1000/decode(sum(executions_delta),0,1,sum(executions_delta)),2) "PL/SQL time msec per exec"
,sum(rows_processed_delta) "Rows processed"
,ROund(sum(rows_processed_delta)/decode(sum(executions_delta),0,1,sum(executions_delta)),4) "Rows per exec"
,Round(sum(buffer_gets_delta)/decode(sum(executions_delta),0,1,sum(executions_delta))) "Buffer gets per exec"
,Round(sum(disk_reads_delta)/decode(sum(executions_delta),0,1,sum(executions_delta))) "Disk reads per exec"
,Round(sum(physical_read_bytes_delta)/decode(sum(executions_delta),0,1,sum(executions_delta))) "Ph read bytes per exec"
,Round(sum(physical_write_bytes_delta)/decode(sum(executions_delta),0,1,sum(executions_delta))) "Ph write bytes per exec"
,ROund(AVG(Version_count)) "Version count"
,Round(AVG(PX_SERVERS_EXECS_DELTA)) "PX Servers"
--,ss.MOdule,ss.action
--,to_char(Substr(t.sql_text,1,200)) "SQL Text"
from dba_hist_Sqlstat ss join dba_hist_snapshot sn on sn.snaP_id=ss.snaP_Id 
left join dba_hist_sqltext t on t.sql_id=ss.sql_id
--where sql_id in ('162pbvuuzajxg','38p7j3kxyvzz5','b7rm4mvwkxfny','356xkrx33fm2t','2cb9xuhy1dknw')
where 1=1 
--and sn.end_interval_Time>sysdate-14
and NVL(t.command_type,1)<>47
--and ss.plan_hash_value=947045001
and ss.sql_id in ('10bq9qfqxqqf2')
    --and sn.end_interval_time>sysdate-30
group by ss.dbid,trunc(sn.end_interval_Time,'hh24')--,ss.snap_id
--,ss.sql_id
,ss.plan_hash_value
--,ss.MOdule,ss.action
--,to_char(Substr(t.sql_text,1,200))--,sn.end_interval_time
order by  trunc(sn.end_interval_Time,'hh24');--,sql_id;--,ss.snap_id;


--Deltas from memory
with sn as
(
select max(cast(trunc(end_interval_Time,'mi') as date)) Last_snapshot_date,
Round((sysdate-to_date(to_char(max(end_interval_Time),'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss'))*24*3600) Duration
from dba_hist_snapshot 
where dbid=(select dbid from gv$database)
and instance_number=(select instance_number from gv$instance)
and trunc(startup_time,'mi')=(select max(trunc(startup_time,'mi')) from dba_hist_database_instance)
)
select 
sn.Last_snapshot_date "Since time"
,sn.Duration "Interval duration,sec"
,ss.SQL_ID
,ss.LAST_ACTIVE_TIME
,ss.PLAN_HASH_VALUE
,DELTA_EXECUTION_COUNT "Delta exec"
,Round(DELTA_EXECUTION_COUNT/sn.Duration,1)  "Delta exec/sec"
,Round(DELTA_EXECUTION_COUNT/sn.Duration/3600,2)  "Delta exec/h"
,Round(DELTA_ROWS_PROCESSED/decode(DELTA_EXECUTION_COUNT,0,1,DELTA_EXECUTION_COUNT),2) "D rows/exec"
,Round(DELTA_BUFFER_GETS/decode(DELTA_EXECUTION_COUNT,0,1,DELTA_EXECUTION_COUNT),2) "D gets/exec"
,Round(DELTA_DIRECT_READS/decode(DELTA_EXECUTION_COUNT,0,1,DELTA_EXECUTION_COUNT),2) "D direct reads/exec"
,Round(DELTA_ELAPSED_TIME/decode(DELTA_EXECUTION_COUNT,0,1,DELTA_EXECUTION_COUNT)/1e6,4) "D elapsed, sec/exec"
,Round(DELTA_CPU_TIME/decode(DELTA_EXECUTION_COUNT,0,1,DELTA_EXECUTION_COUNT)/1e6,4) "D CPU, sec/exec"
,Round(DELTA_APPLICATION_WAIT_TIME/decode(DELTA_EXECUTION_COUNT,0,1,DELTA_EXECUTION_COUNT)/1e6,4) "D App wait, sec/exec"
,Round(DELTA_CONCURRENCY_TIME/decode(DELTA_EXECUTION_COUNT,0,1,DELTA_EXECUTION_COUNT)/1e6,4) "D Concurr, sec/exec"
,Round(DELTA_CLUSTER_WAIT_TIME/decode(DELTA_EXECUTION_COUNT,0,1,DELTA_EXECUTION_COUNT)/1e6,4) "D Cluster, sec/exec"
,Round(DELTA_USER_IO_WAIT_TIME/decode(DELTA_EXECUTION_COUNT,0,1,DELTA_EXECUTION_COUNT)/1e6,4)  "D I/O, sec/exec"
,Round(DELTA_PHYSICAL_READ_REQUESTS/decode(DELTA_EXECUTION_COUNT,0,1,DELTA_EXECUTION_COUNT),2) "D phys read reqs/exec"
,Round(DELTA_PHYSICAL_READ_BYTES/decode(DELTA_EXECUTION_COUNT,0,1,DELTA_EXECUTION_COUNT),2)  "D phys read bytes/exec"
,EXECUTIONS "Executions"
,Round(ROWS_PROCESSED/decode(EXECUTIONS,0,1,EXECUTIONS),2) "Rows per exec"
,Round(BUFFER_GETS/decode(EXECUTIONS,0,1,EXECUTIONS),2) "Gets per exec"
,Round(DISK_READS/decode(EXECUTIONS,0,1,EXECUTIONS),2) "Reads per exec"
,Round(DIRECT_READS/decode(EXECUTIONS,0,1,EXECUTIONS),2) "Direct reads per exec"
,Round(DIRECT_WRITES/decode(EXECUTIONS,0,1,EXECUTIONS),2) "Direct writes per exec"
,Round(CPU_TIME/decode(EXECUTIONS,0,1,EXECUTIONS)/1e6,2) "CPU sec per exec"
,Round(ELAPSED_TIME/decode(EXECUTIONS,0,1,EXECUTIONS)/1e6,2) "Elapsed sec per exec"
,Round(APPLICATION_WAIT_TIME/decode(EXECUTIONS,0,1,EXECUTIONS)/1e6,2) "App wait, sec/exec"
,Round(CONCURRENCY_WAIT_TIME/decode(EXECUTIONS,0,1,EXECUTIONS)/1e6,2) "Concurrency, sec/exec"
,Round(CLUSTER_WAIT_TIME/decode(EXECUTIONS,0,1,EXECUTIONS)/1e6,2) "Cluster, sec/exec"
,Round(USER_IO_WAIT_TIME/decode(EXECUTIONS,0,1,EXECUTIONS)/1e6,2) "User I/O, sec/exec"
,Round(SORTS/decode(EXECUTIONS,0,1,EXECUTIONS),2) "Sorts/exec"
,Round(PHYSICAL_READ_REQUESTS/decode(EXECUTIONS,0,1,EXECUTIONS),2) "Phys read req/exec"
,Round(PHYSICAL_READ_BYTES/decode(EXECUTIONS,0,1,EXECUTIONS),2) "Phys read bytes/exec"
,Round(AVG_HARD_PARSE_TIME/1e6,2) "Hard parse, sec"
,SHARABLE_MEM
,LOADS
,VERSION_COUNT
,INVALIDATIONS
,AVOIDED_EXECUTIONS
,DELTA_AVOIDED_EXECUTIONS
,ss.SQL_TEXT "SQL Text"
from gv$sqlstats ss
    ,sn
where 1=1 
and ss.sql_id in ('10bq9qfqxqqf2')
order by  sql_id,EXECUTIONS desc ;

--Parsing / last exec time and client who parsed
select inst_id,sql_id,plan_hash_value,child_number,first_load_time,last_load_time,object_status,last_active_time,parsing_schema_name,module,action, service,sql_profile,sql_plan_baseline
from gv$sql where sql_id in ('10bq9qfqxqqf2') order by parsing_schema_name, child_number;
select u.username,program,machine,count(*) from gv$active_session_history a
left join dba_users u on a.user_id=u.user_id 
where a.sql_id='10bq9qfqxqqf2' group by u.username,program,machine;

select * from v$instance;
select * from gv$sqlarea where sql_id='10bq9qfqxqqf2';
select sql_id,plan_hash_value, executions,rows_processed,version_count,invalidations,cpu_time/10e6 "CPU, sec", avg_hard_parse_time/10e6 "Parse time, sec", concurrency_wait_time/10e6 "Concurrency,sec",sharable_mem/1024/1024 "SGA mem,MB" from gv$sqlstats where sql_id='10bq9qfqxqqf2';
--===============================================================================
select * from dba_indexes where table_name='DM_SYSOBJECT_S';
select * from dba_ind_columns where table_name='DM_SYSOBJECT_S';
alter index tnf.IDX_SYSOBJECT_NAME_ID invisible;
alter index tnf.D_1F00044D8000000F visible;
create  index GTP.IX_SIG_REMOTE_OBJ on GTP.CROC_DIGITAL_SIGNATURE_S("REMOTE_OBJECT_ID",R_OBJECT_ID) TABLESPACE DM_GTP_INDEX ONLINE;
show parameter optimizer;
--optimizer_index_caching              integer 95       
--optimizer_index_cost_adj             integer 5  
alter system reset optimizer_index_caching scope=both sid='*';
alter system reset optimizer_index_cost_adj scope=both sid='*';
select 'sys @coe_xfr_sql_profile_apply.sql ' || sql_id || ' 3943164985' from v$sql s where sql_text like '%dm_sysobject.r_object_id%r_version_label%dm_sysobject%dm_repeating%object_name%r_object_id%dm_sysobject_r%i_folder_id%dm_sysobject.i_is_deleted%'
and plan_hash_value=3943164985 and sql_profile is null and object_status='VALID';
----------------------------------------------------------------------
-- Plan
----------------------------------------------------------------------
select sql_id,plan_hash_value,child_number,last_active_time,first_load_time,last_load_time,executions,sql_profile,parsing_schema_name from gv$sql where sql_id='10bq9qfqxqqf2' order by parsing_schema_name, child_number;
select inst_id,plan_hash_value,DELTA_EXECUTION_COUNT,executions from gv$sqlstats where sql_id='10bq9qfqxqqf2';
select * from dbms_xplan.display_cursor('10bq9qfqxqqf2' ,0,'ADAPTIVE ALLSTATS ALL');
select * from dbms_xplan.display_awr('10bq9qfqxqqf2',603262634       );
select * from dba_hist_sqltext where sql_id='10bq9qfqxqqf2';

--|*  8 |       INDEX RANGE SCAN                   | IDX$$_FEFD0004     |      1 |    26 |     1   (0)| 00:00:01 |

select  plan_hash_value,min(sql_id),count(distinct sql_id),sum(cpu_time) from v$sqlstats group by plan_hash_value order by sum(cpu_time) desc;
select cpu_time, executions, sql_text from v$sql where plan_hash_value=0 order by cpu_time desc;
select * from dba_objects where object_name=upper('report_task_statistic_history');

select * from dba_sql_profiles order by created desc;
----------------------------------------------------------------------
-- Active session history
----------------------------------------------------------------------
select * from gv$active_session_history where sql_id='10bq9qfqxqqf2';

select NVL(event,'ON CPU'),count(*) from gv$active_session_history where sql_id='10bq9qfqxqqf2' group by NVL(event,'ON CPU') order by count(*) desc;

select top_level_sql_id,count(*) from gv$active_session_history where sql_id='10bq9qfqxqqf2' group by top_level_sql_id order by count(*) desc;
select module,action,program,count(*) from gv$active_session_history where sql_id='10bq9qfqxqqf2' group by module,action,program order by count(*) desc;
select sql_plan_hash_value,sql_plan_line_id,count(*) from gv$active_session_history where sql_id='10bq9qfqxqqf2' 
--and event='direct path read'
group by sql_plan_hash_value,sql_plan_line_id order by sql_plan_hash_value, count(*) desc;

select a.user_id,username,count(*) "Active sessiohs history rows" from gv$active_session_history a join dba_users u on u.user_id=a.user_id where sql_id='10bq9qfqxqqf2' group by a.user_id,username;

--Sampled executions - Active Session History
select cast(max(sample_time) as date) "Sample time", sql_exec_start, sql_id,sql_plan_hash_value "Plan hash val", sql_exec_id--,inst_id
,nvl(qc_session_id,session_id) SID
,sql_exec_id-lag(sql_exec_id) over (order by /*inst_id,*/sql_exec_start,sql_exec_id) "Execs between samples"
,COUNT(case when IN_PARSE='Y' then 1 end) "CNT in parse"
,count(distinct session_id) "Processes"
, Round((cast(max(sample_time) as date) -sql_exec_start)*24*3600,4) "Elapsed, sec"
,Round(max(temp_space_allocated)/1024/1024/1024,3) "Peak temp, GB"
,Round(max(PGA_allocated)/1024/1024) "Peak PGA, MB"
,Round(sum(Delta_read_io_requests),3) "Read, req"
,Round(sum(delta_read_io_bytes)/1024/1024/1024,3) "Read,GB"
--,Round(sum(delta_read_mem_bytes)/1024/1024/1024,3) "Read from mem,GB"
,Round(sum(Delta_write_io_requests),3) "Write, req"
,Round(sum(delta_write_io_bytes)/1024/1024/1024,3) "Write,GB"
,COUNT(case when session_state='ON CPU' then 1 end) "CNT ON CPU"
,COUNT(case when wait_class='Cluster' then 1 end) "CNT Cluster"
,COUNT(case when wait_class='User I/O' then 1 end) "CNT User I/O"
,COUNT(case when event='direct path read temp' then 1 end) "CNT dir p read temp"
,COUNT(case when event='direct path write temp' then 1 end) "CNT dir p write temp"
,COUNT(case when event='direct path read' then 1 end) "CNT dir p read"
,COUNT(case when event='db file sequential read' then 1 end) "CNT db file seq read"
--,Round(AVG(case when event='direct path read temp' then time_waited/1000 end),1) "AVG wait direct path read temp, ms"
--,Round(AVG(case when event='direct path write temp' then time_waited/1000 end),1) "AVG wait direct path write temp, ms"
--,Round(AVG(case when event='db file sequential read' then time_waited/1000 end),1) "AVG wait db file sequential read, ms"
from gv$active_session_history 
--from dba_hist_active_sess_history
where 1=1
and sql_id in ('10bq9qfqxqqf2')--,'5075qnpqqwma9','27fs6a7wdg7mu','5u2545k2yckx4','6r9g69t8b83qb') 
--and sql_plan_hash_value=3127509354
--FORCE_MATCHING_SIGNATURE= 18101390418434877402
and sample_time>sysdate-3
group by --inst_id,
nvl(qc_session_id,session_id), sql_id,sql_exec_id,sql_exec_start,sql_plan_hash_value
order by cast(max(sample_time) as date),sql_exec_id;



select block_size*file_size_blks/1024/1024 "MB" from gv$controlfile;

select owner,JOB_NAME,repeat_interval,job_action, program_name,state,run_count,last_start_date from dba_scheduler_jobs s where JOB_NAME like '%MON' order by 1,2;

select * from dba_ind_columns where table_name='DM_SYSOBJECT_S' --and column_name='OBJECT_NAME'
order by index_name,column_position;
select * from dba_ind_columns where table_name='DM_SYSOBJECT_R' 
order by index_name,column_position;
select * from dba_indexes where index_name='D_1F0002BE8000000F';

select bytes/1024/1024 "MB" from dba_segments where segment_name='DM_SYSOBJECT_S';
select * from dba_index_usage where name='D_1F0002BE8000000F';
select * from v$sql_plan where object_name='D_1F0002BE8000000F';
select sample_time,session_id,sql_id,in_hard_parse,force_matching_signature from gv$active_session_history where force_matching_signature=18101390418434877402;
--sql_plan_hash_value='2920516281';
show parameter optimi

select * from SYS.dba_hist_sqltext where lower(sql_text) like '%dm_repeating.r_version_label%dm_sysobject.object_name%=%:"sys_b_00%';
select * from gv$sqlarea where lower(sql_text) like '%dm_repeating.r_version_label%dm_sysobject.object_name%=%:"sys_b_0%' order by executions desc;

select 
'Alter system kill session '''||s.SID||','||s.SERIAL#||','||'@'||s.INST_ID||''';' as KILL_SESSION
from gv$session s where sql_id='10bq9qfqxqqf2';

select * from v$sql_plan where object_name='IDX_SYSOBJECT_NAME_ID';

select * from dba_objects where object_name in (select index_name from dba_indexes where table_name= 'DM_SYSOBJECT_R');
select  dbms_metadata.get_ddl('INDEX','IDX_SYSOBJECT_NAME_ID','AK') from dual;


select * from dba_hist_sqlstat;
select * from dba_hist_snapshot;
--Top SQL
with params as
(select /*+ NO_MERGE */ min(snap_id)      snap_begin -- Начальный снапшот интервала
         ,max(snap_id)      snap_end   -- Конечный снапшот интервала
         ,d.dbid db_id      -- DBID базы
         ,i.instance_number          inst_num   -- Номер инстанса в случае RAC
         ,10         pct_dbtime  -- Выводить только курсоры выполняющиеся больше pct_dbtime% от DBTime
    from v$instance i,v$database d,dba_hist_snapshot sn where 
    i.instance_number=sn.instance_number
    and d.dbid=sn.dbid
    and sn.begin_interval_time>sysdate-1
    group by d.dbid,i.instance_number
    )
select ss.sql_id,
       ss.module,
       count(distinct plan_hash_value) "Distinct plans",
       SUM(Version_count) "Version count",
       min(dbms_lob.substr(st.SQL_TEXT, 4000, 1)) "SQL Text",
       sum(ss.ELAPSED_TIME_DELTA) / 1000000 "Elapsed Time(s)",
       sum(ss.CPU_TIME_DELTA) / 1000000 "CPU Time(s)",
       sum(ss.executions_delta) "Executions",
       sum(ss.ROWS_PROCESSED_DELTA) "Rows processed",
       sum(ss.BUFFER_GETS_DELTA) "Buffer Gets",
       sum(ss.physical_read_requests_delta) "Physical Reads reqs",
       sum(ss.physical_read_bytes_delta)/1024/1024 "Physical Reads MBytes",
       sum(ss.iowait_delta) / 1000000 "IO Wait, sec",
       sum(ss.ccwait_delta) / 1000000 "Concurrency, sec",
       sum(ss.apwait_delta) / 1000000 "Application, sec",
       sum(ss.clwait_delta) / 1000000 "Cluster, sec",
       sum(ss.BUFFER_GETS_DELTA) /
       decode(sum(ss.ROWS_PROCESSED_DELTA),
              0,
              1,
              sum(ss.ROWS_PROCESSED_DELTA)) gets_per_row,
       sum(ss.DISK_READS_DELTA) /
       decode(sum(ss.ROWS_PROCESSED_DELTA),
              0,
              1,
              sum(ss.ROWS_PROCESSED_DELTA)) prds_per_row,
       sum(ss.BUFFER_GETS_DELTA) /
       decode(sum(ss.executions_delta), 0, 1, sum(ss.executions_delta)) gets_per_exec
  from dba_hist_sqlstat ss, dba_hist_sqltext st, params
where ss.SQL_ID = st.SQL_ID
   and ss.DBID = st.DBID
   and st.COMMAND_TYPE not in (47, 170) -- 47-PL/SQL EXECUTE 170-CALL METHOD
   and ss.snap_id between params.snap_begin + 1 and params.snap_end
   and ss.DBID = params.db_id
   and ss.instance_number = params.inst_num
group by ss.sql_id, ss.module
having ((sum(ss.ELAPSED_TIME_DELTA) / 1000000) / (select max(ss2.value - ss1.value) /  1000000 db_time
                                              from dba_hist_sys_time_model ss1,
                                                   dba_hist_sys_time_model ss2,
                                                   params                  pr
                                             where ss1.dbid = pr.db_id
                                               and ss1.stat_name =
                                                   'DB time'
                                               and ss1.stat_id =  ss2.stat_id
                                               and ss1.dbid = ss2.dbid
                                               and ss1.INSTANCE_NUMBER = ss2.INSTANCE_NUMBER
                                               and ss1.INSTANCE_NUMBER = pr.instance_number
                                               and ss1.snap_id = pr.snap_begin
                                               and ss2.snap_id = pr.snap_end)) > max (params.pct_dbtime/100)
order by 4 desc;


select * from dba_ind_columns where table_name='CROC_ADDITIONAL_VISA_S';
select * from dba_indexes where table_name='CROC_ADDITIONAL_VISA_S';
select * from v$active_session_history where sql_opname='CREATE INDEX';
select * from v$sqlarea where sql_id='ahbrkznhn0k9c';
select * from v$session where sid=4185;
select * from dba_segments where segment_name='IDX_PARNT_VISA_ID';
select 2781872128/1024/1024 from dual;
select * from v$session where sql_id='a9k9b43hknmcv';
exec dbms_repair.online_index_clean(1967631);
select * from dba_objects where object_name='IDX_PARNT_VISA_ID';
select sid,serial#,inst_id,sql_id from gv$session where  username='TNF'  and osuser='dmadmin' and module='documentum@VDC01-PETNFCSN1 (TNS V1-V3)'
and sql_exec_start<sysdate-3/1440 and status='ACTIVE' and event='direct path read'
order by sid;
select * from unifid_aiud