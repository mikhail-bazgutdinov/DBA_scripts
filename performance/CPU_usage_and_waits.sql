--======================================================================================
-- Sysmetric history
-- Потребление CPU и несколько ключевых метрик базы
-- Усреднение поминутное.
--======================================================================================
select begin_time
,sum(case when metric_name='Host CPU Usage Per Sec' then Round(value) end) "Host CPU Usage Per Sec" 
,sum(case when metric_name='Average Active Sessions' then Round(value) end) "Average Active Sessions" 
,sum(case when metric_name='User Transaction Per Sec' then Round(value) end) "User Transaction Per Sec" 
,sum(case when metric_name='Average Synchronous Single-Block Read Latency' then Round(value,4) end) "Average Synchronous Single-Block Read Latency" 
,sum(case when metric_name='Physical Writes Per Sec' then Round(value) end) "Physical Writes, Blocks Per Sec" 
,sum(case when metric_name='Physical Reads Per Sec' then Round(value) end) "Physical Reads, Blocks Per Sec" 
from --DBA_HIST_SYSMETRIC_HISTORY  -- Здесь данные из AWR
v$sysmetric_history  -- Здесь последний час работы базы
where 
begin_time > sysdate-1  
and metric_name in ('User Transaction Per Sec','Host CPU Usage Per Sec','Average Active Sessions','Average Synchronous Single-Block Read Latency','User Transaction Per Sec','Physical Writes Per Sec','Physical Reads Per Sec')
and group_id=2
group by --dbid,
begin_time
order by begin_time desc;

--======================================================================================
-- By Waitclasses
-- Из ASH
-- Сэмплирование 1-сек (v$) или 10-сек (dba_hist)
--======================================================================================
SELECT 
  TO_CHAR(SES.SAMPLE_TIME,'yyyy-mm-dd') "Sample date",
  TO_CHAR(SES.SAMPLE_TIME,'hh24:mi:ss') "Sample time",
  COUNT(*) "Total",
  COUNT(distinct sample_id) "Number of snapshots",
  COUNT(DECODE(SES.session_State,'ON CPU',1)) "Sessions on CPU",
  Round(SUM(TM_DELTA_CPU_TIME)/1e6,1) "Delta CPU time,sec",
  COUNT(DECODE(SES.WAIT_CLASS,'Administrative',1)) "Administrative",
  COUNT(DECODE(SES.WAIT_CLASS,'Application',1)) "Application",
  COUNT(DECODE(SES.WAIT_CLASS,'Cluster',1)) "Cluster",
  COUNT(DECODE(SES.WAIT_CLASS,'Commit',1)) "Commit",
  COUNT(DECODE(SES.WAIT_CLASS,'Concurrency',1)) "Concurrency",
  COUNT(DECODE(SES.WAIT_CLASS,'Configuration',1)) "Configuration",
  COUNT(DECODE(SES.WAIT_CLASS,'Network',1)) "Network",
  COUNT(DECODE(SES.WAIT_CLASS,'Other',1)) "Other",
  COUNT(DECODE(SES.WAIT_CLASS,'Scheduler',1)) "Scheduler",
  COUNT(DECODE(SES.WAIT_CLASS,'System I/O',1)) "System I/O",
  COUNT(DECODE(SES.WAIT_CLASS,'User I/O',1)) "User I/O"
FROM 
  --DBA_HIST_ACTIVE_SESS_HISTORY SES
  --ASH_db_210210141842 SES
  V$ACTIVE_SESSION_HISTORY SES
WHERE 1=1
  --and SES.SESSION_STATE='WAITING'
  --and SES.SAMPLE_TIME>sysdate-1/24/60
  AND SES.SAMPLE_TIME between to_date('20.04.2022 00:00:00','dd.mm.yyyy hh24:mi:ss') and to_date('20.04.2022 10:00:00','dd.mm.yyyy hh24:mi:ss')
GROUP BY 
  TO_CHAR(SES.SAMPLE_TIME,'yyyy-mm-dd'),
  TO_CHAR(SES.SAMPLE_TIME,'hh24:mi:ss')
ORDER BY 
  --TO_CHAR(SES.SAMPLE_TIME,'yyyy-mm-dd'),
  TO_CHAR(SES.SAMPLE_TIME,'hh24:mi:ss');



--======================================================================================
-- Different Top's based on ASH
--Закомментировать "лишние" колонки
--Или раскомментировать нужные
--======================================================================================
select 
    to_char(sample_time,'dd.mm.yyyy hh24')  "Time"
--  ,ash.session_id sid
--  ,ash.session_serial# serial#
     ,ash.user_id
     ,ash.program
	 ,ash.machine
	 ,ash.module
	 ,ash.action
--	 ,ash.sql_id
--	 ,ash.sql_exec_id
--	 ,ash.sql_exec_start
--	 ,ash.sql_plan_hash_value
--	 ,ash.sql_plan_line_id
--	 ,ash.sql_opname
--	 ,ash.top_level_sql_id
--	 ,ash.sql_plan_operation || ' ' || ash.sql_plan_options "Plan operation"
--	 ,ash.plsql_entry_object_id
--	 ,ash.plsql_entry_subprogram_id
--	 ,ash.plsql_object_id
--	 ,ash.plsql_subprogram_id
--	 ,nvl(ash.event,ash.session_state) "Event"
--	 ,ash.wait_class
     ,sum(decode(ash.session_state,'ON CPU',1,0))     "Samples on CPU"
     ,sum(decode(ash.session_state,'WAITING',1,0))    -
     sum(decode(ash.session_state,'WAITING',
        decode(wait_class,'User I/O',1, 0 ), 0))    "Samples in wait" 
     ,sum(decode(ash.session_state,'WAITING',
        decode(wait_class,'User I/O',1, 0 ), 0))    "Samples on IO" 
     ,sum(decode(session_state,'ON CPU',1,1))     "Samples total"
from v$active_session_history ash
WHERE 1=1
--uncomment below lines for filtering on timeframe
--and sample_time>sysdate-10/1440 -- 10 last minutes
--and sample_time between to_date('20.04.2022 08:00:00','dd.mm.yyyy hh24:mi:ss') and to_date('20.04.2022 08:00:00','dd.mm.yyyy hh24:mi:ss')
group by 
    to_char(sample_time,'dd.mm.yyyy hh24')
--   ,ash.session_id
--   ,ash.session_serial#
     ,ash.user_id
     ,ash.program
	 ,ash.machine
	 ,ash.module
	 ,ash.action
--	 ,ash.sql_id
--	 ,ash.sql_exec_id
--	 ,ash.sql_exec_start
--	 ,ash.sql_plan_hash_value
--	 ,ash.sql_plan_line_id
--	 ,ash.sql_opname
--	 ,ash.top_level_sql_id
--	 ,ash.sql_plan_operation || ' ' || ash.sql_plan_options
--	 ,ash.plsql_entry_object_id
--	 ,ash.plsql_entry_subprogram_id
--	 ,ash.plsql_object_id
--	 ,ash.plsql_subprogram_id
--	 ,nvl(ash.event,ash.session_state)
--	 ,ash.wait_class
order by "Time" desc, sum(decode(session_state,'ON CPU',1,1)) desc;

--======================================================================================
-- Top sessions with usernames and connected/disconnected status. 
-- Based on https://github.com/khailey-zz/ashmasters/blob/master/ash_top_session.sql
--======================================================================================
col name for a12
col program for a25
col CPU for 9999
col IO for 9999
col TOTAL for 99999
col WAIT for 9999
col user_id for 99999
col sid for 9999

set linesize 120

select
        decode(nvl(to_char(s.sid),-1),-1,'DISCONNECTED','CONNECTED')
                                                        "STATUS",
        topsession.sid             "SID",
        u.username  "NAME",
        topsession.program                  "PROGRAM",
        max(topsession.CPU)              "Samples on CPU",
        max(topsession.WAIT)       "Samples in wait",
        max(topsession.IO)                  "Samples on IO",
        max(topsession.TOTAL)           "Samples total"
        from (
select * from (
select
     ash.session_id sid,
     ash.session_serial# serial#,
     ash.user_id user_id,
     ash.program,
     sum(decode(ash.session_state,'ON CPU',1,0))     "CPU",
     sum(decode(ash.session_state,'WAITING',1,0))    -
     sum(decode(ash.session_state,'WAITING',
        decode(wait_class,'User I/O',1, 0 ), 0))    "WAIT" ,
     sum(decode(ash.session_state,'WAITING',
        decode(wait_class,'User I/O',1, 0 ), 0))    "IO" ,
     sum(decode(session_state,'ON CPU',1,1))     "TOTAL"
from v$active_session_history ash
WHERE 1=1
--uncomment below lines for filtering on timeframe
and sample_time>sysdate-10/1440 -- 10 last minutes
--and sample_time between to_date('20.04.2022 08:00:00','dd.mm.yyyy hh24:mi:ss') and to_date('20.04.2022 08:00:00','dd.mm.yyyy hh24:mi:ss')
group by session_id,user_id,session_serial#,program
order by sum(decode(session_state,'ON CPU',1,1)) desc
) where rownum < 10
   )    topsession,
        v$session s,
        all_users u
   where
        u.user_id =topsession.user_id and
        /* outer join to v$session because the session might be disconnected */
        topsession.sid         = s.sid         (+) and
        topsession.serial# = s.serial#   (+)
   group by  topsession.sid, topsession.serial#,
             topsession.user_id, topsession.program, s.username,
             s.sid,s.paddr,u.username
   order by max(topsession.TOTAL) desc;