-- Top 2 WAIT events and redo amount written by LGW
--from memory
with
ASH as
(
SELECT ASH.SAMPLE_TIME,
  ASH.EVENT,
  ROUND(AVG(TM_DELTA_TIME)/1000000,2) "Time spent,sec",
  COUNT(*) COUNT_SES,
  AVG(decode(time_waited,0,null,time_waited)) avg_time_waited,
  rank() over (partition by ash.SAMPLE_TIME order by count(*) desc, AVG(decode(time_waited,0,null,time_waited)) desc) Rank 
FROM 
    v$active_session_history  ASH
WHERE 
1=1
--and sql_id='6wx234zagavhm'
  --and ASH.SESSION_STATE='WAITING'
-- and ASH.WAIT_CLASS IN ('Concurrency')
--and ASH.SAMPLE_TIME>sysdate-1/24/60*15
--and ash.event like 'log file sync'
 -- and ash.INSTANCE_NUMBER=1
  --and ash ses.snap_id between 425900 and 426999
 -- and snap_id in (211748,211749) 
 -- and ash.dbid=1638121219
 -- and ash.con_dbid=1638121219
--AND ASH.SAMPLE_TIME between to_date('09.01.2019 00:00:16','dd.mm.yyyy hh24:mi:ss') and to_date('09.01.2019 01:17:16','dd.mm.yyyy hh24:mi:ss')
--and (program like '%SMON%')
group by ash.SAMPLE_TIME,ash.event 
order by ash.SAMPLE_TIME, COUNT(*) desc
),
ASH_t as
(
SELECT ASH.SAMPLE_TIME,
  COUNT(*) COUNT_SES,
  Round(SUM(DELTA_READ_IO_BYTES)/1024/1024) "Total read MB",
  Round(SUM(DELTA_WRITE_IO_BYTES)/1024/1024) "Total write MB",
  Round(SUM(DELTA_READ_IO_REQUESTS)) "Total read req",
  Round(SUM(DELTA_WRITE_IO_REQUESTS)/1024/1024) "Total write req"
FROM 
   v$active_session_history ASH
group by ash.SAMPLE_TIME
),
LGW_STAT as 
(
select 
  SES.SAMPLE_TIME,
  EVENT,
  COUNT(*) "Sess in log file paral wr",
  ROUND(SUM(DELTA_TIME)/1000000,2) "Time spent,sec", 
  AVG(decode(time_waited,0,null,time_waited)) avg_time_waited, 
  Round(SUM(DELTA_WRITE_IO_BYTES)/1024/1024) "Written, Mb"
FROM 
 v$active_session_history SES
WHERE 
  --SESSION_STATE='WAITING'
--and -- event='log file parallel write'
 program like '%LGWR%'
group by SES.SAMPLE_TIME,EVENT
order by SES.SAMPLE_TIME, COUNT(*) desc
)
select 
      TO_DATE(TO_CHAR(ASH1.SAMPLE_TIME,'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss') "Sample time", 
      TO_CHAR(ASH1.SAMPLE_TIME,'hh24:mi:ss') "Time", 
      ASH_t.COUNT_SES "Total sess count",
      ASH_t."Total read MB",
      ASH_t."Total write MB",
      ASH_t."Total read req",
      ASH_t."Total write req",
      --ASH1."Time spent,sec", 
      NVL(ASH1.EVENT,'On CPU') "Top1 event",  
      ASH1.COUNT_SES "Top1 count sess",
      Round(ASH1.avg_time_waited/1000,1) "Top1 event avg wait,msec",
      NVL(ASH2.EVENT,'On CPU') "Top2 event",  
      ASH2.COUNT_SES "Top2 count sess", 
      Round(ASH2.avg_time_waited/1000,1) "Top2 event avg wait,msec",
      ROUND(LGW_STAT."Written, Mb"/LGW_STAT."Time spent,sec") "Written by LGW, Mb/sec",
      LGW_STAT.Event "LGWR wait event",
      Round(LGW_STAT.avg_time_waited/1000,1) "LGWR waited,ms"
    --  LGW_STAT."Time waited,sec" "Time spent by LGW,sec"
from (select * from ASH where RANK=1) ASH1 
LEFT JOIN (SELECT * FROM ASH WHERE RANK=2) ASH2 ON ASH1.SAMPLE_TIME=ASH2.SAMPLE_TIME
LEFT JOIN LGW_STAT ON LGW_STAT.SAMPLE_TIME=ASH1.SAMPLE_TIME
LEFT JOIN ASH_t on ASH_t.sample_time=ASH1.sample_time
--where ASH1.EVENT='log file sync'
--where ASH1.COUNT_SES>10
--where Round(LGW_STAT.avg_time_waited/1000,1)>30
ORDER BY ASH1.SAMPLE_TIME desc;

set serveroutput on buffer 10000
select * from mbazgutdinov.ashtop(mbazgutdinov.ASH_DBDPC_210224150848,4);
select * from mbazgutdinov.SYSMETR(MBAZGUTDINOV.SYSMETR_ERMB_210212175551,60);

select * from dba_hist_sqlstat;

select sql_id from v$session where event='latch: cache buffers chains';
select sql_id from v$session where event='enq: SS - contention';
  select sql_text from v$sql where sql_id='6g130gh3ygsny';


-- Top WAIT events 
--from v$session_wait_history (10 last waits)
with
SWH as
(
SELECT SWH.SEQ#,
  SWH.EVENT,
  COUNT(*) COUNT_SES,
  AVG(WAIT_TIME_MICRO) WAIT_TIME_MICRO,
  AVG(TIME_SINCE_LAST_WAIT_MICRO) TIME_SINCE_LAST_WAIT_MICRO,
  rank() over (partition by SWH.SEQ# order by COUNT(*) desc, SUM(WAIT_TIME_MICRO) desc) Rank 
FROM 
  V$SESSION_WAIT_HISTORY SWH
where swh.event not in ('SQL*Net message from client','rdbms ipc message','SQL*Net break/reset to client')  
and swh.event not like '%idle wait'
and not (swh.event in ('SQL*Net message to client','SQL*Net more data from client') and WAIT_TIME_MICRO<1000)
group by SWH.SEQ#, SWH.EVENT 
)
select 
      SWH1.SEQ#, 
      SWH1.EVENT "Top1 event",  
      SWH1.COUNT_SES "Top1 count sess",
      Round(SWH1.WAIT_TIME_MICRO/1000,1) "Top1 avg wait,msec",
      Round(SWH1.TIME_SINCE_LAST_WAIT_MICRO/1000,1) "Top1 avg tim sinc last wait,ms",
      SWH2.EVENT "Top2 event",  
      SWH2.COUNT_SES "Top2 count sess",
      Round(SWH2.WAIT_TIME_MICRO/1000,1) "Top2 avg wait,msec",
      Round(SWH2.TIME_SINCE_LAST_WAIT_MICRO/1000,1) "Top2 avg tim sinc last wait,ms",
      SWH3.EVENT "Top3 event",  
      SWH3.COUNT_SES "Top3 count sess",
      Round(SWH3.WAIT_TIME_MICRO/1000,1) "Top3 avg wait,msec",
      Round(SWH3.TIME_SINCE_LAST_WAIT_MICRO/1000,1) "Top3 avg tim sinc last wait,ms"
from (select * from SWH where RANK=1) SWH1
LEFT JOIN (SELECT * FROM SWH WHERE RANK=2) SWH2 ON SWH1.SEQ#=SWH2.SEQ#
LEFT JOIN (SELECT * FROM SWH WHERE RANK=3) SWH3 ON SWH1.SEQ#=SWH3.SEQ#
ORDER BY SWH1.SEQ#;


--select * from dba_objects where object_name='OPT_F9_TBL' order by created desc;
---
---grouping by some fields from ASH
with waits as (
select event
--, sql_id--,(select sql_text from gv$sql s where s.sql_id=ash.sql_id and rownum=1) sql_text,
,force_matching_signature
--sample_time, 
--,p1,p2,p3
--sample_id,
--,blocking_session,blocking_session_serial#, ash.BLOCKING_INST_ID,BLOCKING_HANGCHAIN_INFO
--current_obj#,
,count(*) samples_count,
Round(avg(time_waited)/1000) "Avg wait time, msec"
from v$active_session_history ash 
where 
--event in ('library cache: mutex X') and 
event is null
sample_time>sysdate-1/24/60*15 --to_date('2015-11-03 01:20','yyyy-mm-dd hh24:mi')
--and 
--to_char(sample_time,'dd.mm.yy hh24:mi:ss')='03.11.15 01:27:29'
group by event
,force_matching_signature
--,sql_id
--,p1,p2,p3
--sample_time, 
--,sample_id
--,blocking_session,blocking_session_serial#, BLOCKING_INST_ID,BLOCKING_HANGCHAIN_INFO
--,current_obj#
--order by sample_time desc;
order by count(*) desc
)
select 
force_matching_signature
--sql_id
--p1,p2,p3
--,blocking_session
--,blocking_session_serial#
--, BLOCKING_INST_ID
, samples_count
, "Avg wait time, msec"
, "Avg wait time, msec"*samples_count "Total"
from waits
order by "Total" desc;
--select sql_id,sql_text,samples_count,"Avg wait time, msec",
--SUBSTR(waits.sqL_text,8,instr(waits.sqL_text,'.')-8) sequence,
--(select CACHE_SIZE from dba_sequences where SEQUENCE_NAME=SUBSTR(waits.sqL_text,8,instr(waits.sqL_text,'.')-8) and sequence_owner='OWS') CACHE_SIZE
--from waits;

select p1,count(*) from v$session where event='library cache: mutex X' group by p1 order by count(*) desc;

select * from V$DB_OBJECT_CACHE
where hash_value=1589267268;

select * from dba_segments where segment_name='CSA_CODLOG_S';
select partition_name,segment_created,count(*) from dba_tab_subpartitions where table_name='CSA_CODLOG_S' group by partition_name,segment_created;



select  * from dba_tables where table_name='CSA_CODLOG_S';
select * from v$rowcache where cache#=13;

select * from v$active_session_history where session_id=1882 and session_serial#=2657 and sample_time>to_date('2015-12-22 21:55','yyyy-mm-dd hh24:mi');

select * from v$sql where sql_id='6wx234zagavhm';

select * from CHALNA_DBDPC_MG_MAIN.dba_hist_snapshot order by snap_id desc;

-- Top 2 WAIT events and redo amount written by LGW 
-- from AWR

select * from dba_hist_snapshot order by snap_id desc;
with
ASH_filtered as
(
select 
ses.*
FROM 
dba_hist_active_sess_history SES
where  1=1
--  ses.sample_time >sysdate-1/24--between TO_DATE('22.07.2014 00:10','dd.mm.yyyy hh24:mi') and TO_DATE('22.07.2014 17:15','dd.mm.yyyy hh24:mi')
and SAMPLE_TIME between to_date('23.12.2022 09:00:30','dd.mm.yyyy hh24:mi:ss') and to_date('23.12.2022 14:17:30','dd.mm.yyyy hh24:mi:ss')
	--  SES.SAMPLE_TIME between to_date('21.07.2016 12:00:00','dd.mm.yyyy hh24:mi:ss') and to_date('21.07.2016 14:30:00','dd.mm.yyyy hh24:mi:ss')
  and snap_id between 98179 and 98193 
  and ses.dbid=1303994287
  --and ses.con_dbid=1638121219 
--AND SAMPLE_TIME between to_date('09.01.2019 00:30:00','dd.mm.yyyy hh24:mi:ss') and to_date('09.01.2019 01:10:00','dd.mm.yyyy hh24:mi:ss')
--and ses.instance_number=1
--and ses.snap_id between 271562 and 271562
--  and ses.wait_class='Concurrency'
 --and (ses.event='Disk file operations I/O' or (program like '%MMON%' or program like '%(M%') or program like 'oracle@%(P%)' )
-- and (ses.event='log file parallel write')
 --and action='DDE async action'
 --and (program like '%DBW%')
order by sample_time
)
,
ASH as
(
select SES.SAMPLE_TIME,SES.EVENT,COUNT(*) count_ses,
AVG(decode(time_waited,0,null,time_waited)) avg_time_waited,
rank() over (partition by SES.SAMPLE_TIME order by count(*) desc) Rank 
from 
ash_filtered SES
where
1=1
  --and SES.WAIT_CLASS IN ('Concurrency','Configuration','Other')
--and SESSION_STATE='WAITING'
--and event like 'library%'
--and program like '%SMON%'
-- and event is not null and event not in('db file sequential read','read by other session','db file parallel write','db file scattered read')
--and SQL_ID='a5vg9vbnakju8'
group by SES.SAMPLE_TIME,event
order by SES.SAMPLE_TIME, COUNT(*) desc
),
ASH_t as
(
SELECT ASH.SAMPLE_TIME,
  COUNT(*) COUNT_SES,
  Round(SUM(PGA_ALLOCATED)/1024/1024) "PGA Alloc, MB",
  Round(SUM(DELTA_READ_IO_BYTES)/1024/1024) "Total read MB",
  Round(SUM(DELTA_WRITE_IO_BYTES)/1024/1024) "Total write MB",
  Round(SUM(DELTA_READ_IO_REQUESTS)) "Total read req",
  Round(SUM(DELTA_WRITE_IO_REQUESTS)/1024/1024) "Total write req"
FROM 
  ash_filtered ASH
group by ash.SAMPLE_TIME
),
DBW_STAT as 
(
select 
  SES.SAMPLE_TIME,
  Max(EVENT) Event,
  COUNT(*) "DBWR processes",
  ROUND(AVG(DELTA_TIME)/1000000,2) "Time spent,sec", 
  Round(SUM(TM_DELTA_DB_TIME)/1000000,2) "Time waited,sec", 
  Round(SUM(DELTA_WRITE_IO_REQUESTS)) "Write requests",
  Round(SUM(DELTA_WRITE_IO_BYTES)/1024/1024) "Written, Mb"
from 
ash_filtered  SES
WHERE 
  1=1
  and program like '%DBW%'
--and SESSION_STATE='WAITING'
--and event='log file parallel write'
group by SES.SAMPLE_TIME
order by SES.SAMPLE_TIME, COUNT(*) desc
)
,
LGW_STAT as 
(
select 
  SES.SAMPLE_TIME,
  Max(EVENT) Event,
  COUNT(*) "LGWR processes",
  ROUND(AVG(DELTA_TIME)/1000000,2) "Time spent,sec", 
  Round(SUM(TM_DELTA_DB_TIME)/1000000,2) "Time waited,sec", 
  Round(SUM(DELTA_WRITE_IO_REQUESTS)) "Write requests",
  Round(SUM(DELTA_WRITE_IO_BYTES)/1024/1024) "Written, Mb"
from 
ash_filtered  SES
WHERE 
  1=1
  and program like '%LG%'
--and SESSION_STATE='WAITING'
--and event='log file parallel write'
group by SES.SAMPLE_TIME
order by SES.SAMPLE_TIME, COUNT(*) desc
)
select 
      TO_DATE(TO_CHAR(ASH1.SAMPLE_TIME,'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss') "Sample time", 
      to_char(ASH1.SAMPLE_TIME,'hh24:mi:ss') "Time", 
      ASH_t.COUNT_SES "Total active sess count",
      ASH_t."PGA Alloc, MB",
      ASH_t."Total read MB",
      ASH_t."Total write MB",
      ASH_t."Total read req",
      ASH_t."Total write req",
      case when ASH_t.COUNT_SES>1500 then '!!!!!!!' else ' ' end "Warning",
      DBW_STAT."Time spent,sec", 
      NVL(ASH1.EVENT,'on CPU') "Top1 event",  
      ASH1.COUNT_SES "Top1 count sess",
      Round(ASH1.avg_time_waited/1000,1) "Top1 event avg wait,msec",
      NVL(ASH2.EVENT,'on CPU') "Top2 event",  
      ASH2.COUNT_SES "Top2 count sess", 
      Round(ASH2.avg_time_waited/1000,1) "Top2 event avg wait,msec",
      NVL(ASH3.EVENT,'on CPU') "Top3 event",  
      ASH3.COUNT_SES "Top3 count sess", 
      Round(ASH3.avg_time_waited/1000,1) "Top3 event avg wait,msec",
      Round(LGW_STAT."Write requests"/LGW_STAT."Time spent,sec") "Write reqs by LGWR/sec",
      Round(LGW_STAT."Written, Mb"/LGW_STAT."Time spent,sec") "Written by LGWR, Mb/sec",
      LGW_STAT."LGWR processes",
      Round(DBW_STAT."Write requests"/DBW_STAT."Time spent,sec") "Write reqs by DBWRs/sec",
      Round(DBW_STAT."Written, Mb"/DBW_STAT."Time spent,sec") "Written by DBWRs, Mb/sec",
      DBW_STAT."DBWR processes"
from (select * from ASH where RANK=1) ASH1 
LEFT JOIN (SELECT * FROM ASH WHERE RANK=2) ASH2 ON ASH1.SAMPLE_TIME=ASH2.SAMPLE_TIME
LEFT JOIN (SELECT * FROM ASH WHERE RANK=3) ASH3 ON ASH1.SAMPLE_TIME=ASH3.SAMPLE_TIME
LEFT JOIN DBW_STAT ON DBW_STAT.SAMPLE_TIME=ASH1.SAMPLE_TIME
LEFT JOIN LGW_STAT ON LGW_STAT.SAMPLE_TIME=ASH1.SAMPLE_TIME
LEFT JOIN ASH_t on ASH_t.sample_time=ASH1.sample_time
--where ASH1.EVENT='log file sync' and ASH1.COUNT_SES>200
order by ASH1.SAMPLE_TIME ;




alter system set "_diag_hm_rc_enabled"=TRUE scope=memory;

select nam.ksppinm NAME, val.KSPPSTVL VALUE,nam.ksppdesc "Description"
from sys.x$ksppi nam, sys.x$ksppsv val
where nam.indx = val.indx and (nam.ksppdesc like '%HM%')
order by 1;
select * from v$datafile;

select * from v$diag_info;

show parameter slave
select *
FROM 
CHALNA_DBDPC_MG_MAIN.DBA_HIST_ACTIVE_SESS_HISTORY SES;

select * from CHALNA_DBDPC_MG_MAIN.DBA_HIST_SNAPSHOT order by snap_id desc;

select * from v$system_event;

select * from SYS.DBA_HIST_SYSTEM_EVENT where event_name='log file sync' order by snap_id desc;
select * from v$instance;
select * from CHALNA_DBDPC_MG_MAIN.dba_hist_snapshot order by snap_id desc;

with
ASH_filtered as
(
    select /*+ MATERIALIZE NO_MERGE */
    *
    FROM 
    DBA_HIST_ACTIVE_SESS_HISTORY SES
    where  1=1
    --  ses.sample_time >sysdate-1/2
    --  SES.SAMPLE_TIME between to_date('21.07.2016 12:00:00','dd.mm.yyyy hh24:mi:ss') and to_date('21.07.2016 14:30:00','dd.mm.yyyy hh24:mi:ss')
      and ses.INSTANCE_NUMBER=1
      and ses.snap_id between 24500	 and 26000
      and ses.dbid=2271394354
    --  and ses.con_dbid=1638121219
      and ses.wait_class='Concurrency'
    -- and ses.event='library cache lock'
    --and (program like '%SMON%' or program like '%LGWR%')
    --or program like 'oracle@%(P%)' and action='SYS_IMPORT_FULL_01'
)
,
ASH as
(
select 
    SES.SAMPLE_TIME,
    SES.SQL_ID || ' - ' || SES.SQL_PLAN_HASH_VALUE || ', plan line - ' || SQL_PLAN_LINE_ID || ', plan operation - ' || SQL_PLAN_OPERATION || ' ' || SQL_PLAN_OPTIONS "SQL"
    ,COUNT(*) count_ses,
    COUNT(decode(ses.IN_SQL_EXECUTION,'Y',1)) "Sess in SQL execution",
    COUNT(decode(ses.IN_HARD_PARSE,'Y',1)) "Sess in hard parse",
    to_char(MIN (SQL_EXEC_START),'hh24:mi:ss') "Earliest SQL exec started",
    Round(SUM(DELTA_READ_IO_BYTES/1024/1024)/(AVG(DELTA_TIME)/1000000),2) "Mb read/sec",
    rank() over (partition by SES.SAMPLE_TIME order by count(*) desc) Rank 
from 
ash_filtered SES
where
1=1
  --and SES.WAIT_CLASS IN ('Concurrency','Configuration','Other')
--and SESSION_STATE='WAITING'
--and event like 'library%'
--and program like '%SMON%'
group by SES.SAMPLE_TIME,SES.SQL_ID , SES.SQL_PLAN_HASH_VALUE, SQL_PLAN_LINE_ID, SQL_PLAN_OPERATION,SQL_PLAN_OPTIONS
order by SES.SAMPLE_TIME, COUNT(*) desc
),
ASH_t as
(
SELECT ASH.SAMPLE_TIME,
  COUNT(*) COUNT_SES
FROM 
  ash_filtered ASH
group by ash.SAMPLE_TIME
)
select 
      TO_DATE(TO_CHAR(ASH1.SAMPLE_TIME,'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss') "Sample time", 
      to_char(ASH1.SAMPLE_TIME,'hh24:mi:ss') "Time", 
      ASH_t.COUNT_SES "Total sess count",
      ASH1.SQL "Top1 SQL",  
      ASH1.COUNT_SES "Top1 count sess",
      ASH1."Sess in SQL execution" "Top1 - sessions in SQL execution",
      ASH1."Sess in hard parse" "Top1 - sessions in hard parse",
      ASH1."Mb read/sec",
      ASH1."Earliest SQL exec started" "Top1 - earliest SQL execution started",
      ASH2.SQL "Top2 SQL",  
      ASH2.COUNT_SES "Top2 count sess", 
      ASH2."Sess in SQL execution" "Top2 - sessions in SQL execution",
      ASH2."Sess in hard parse" "Top2 - sessions in hard parse"
from (select * from ASH where RANK=1) ASH1 
LEFT JOIN (SELECT * FROM ASH WHERE RANK=2) ASH2 ON ASH1.SAMPLE_TIME=ASH2.SAMPLE_TIME
LEFT JOIN ASH_t on ASH_t.sample_time=ASH1.sample_time
--where ASH1.SQL Like '4d5vq9bwtx9x1%' 
--and ASH1.COUNT_SES>6
order by ASH1.SAMPLE_TIME desc;
select instance_number, min(snap_id), max(snap_id) from dba_hist_snapshot 
where 
end_interval_time between to_date('21.07.2016 12:00:00','dd.mm.yyyy hh24:mi:ss') and to_date('21.07.2016 15:00:00','dd.mm.yyyy hh24:mi:ss')
group by instance_number
order by instance_number;

select * from dba_hist_snapshot order by end_interval_time desc;
select * from dba_tables order by last_analyzed desc nulls last;


show parameter commit

--Some information from v$session
select s.wait_class, s.state,s.event,s.status,count(*) 
from v$session s join v$active_session_history ash on s.sid=ash.session_id--where status='ACTIVE'
where ash.sample_time=(select max(sample_Time) from v$active_session_history)
and ash.session_state='ON CPU'
group by s.wait_class, s.state,s.status,s.event
order by count(*) desc;
select count (*) from v$session;


select * from v$active_session_history where 
cast(sample_time as date)=to_date('14.10.15 02:19:32','dd.mm.yy hh24:mi:ss');
--program like '%LGWR%';
--select * from dba_objects where object_name='IX_AUD_SEC_EVENT_TYPE';
select * from gv$active_session_history where session_type='BACKGROUND' and program like '%RVWR%' order by sample_time desc;

select * from v$active_session_history where to_char(sample_time,'hh24:mi:ss')='08:54:26' 
order by sample_time,event,session_id;

select * from v$active_session_history where 
--session_id=5614 and session_serial#=57157
event='latch: cache buffers chains'
and 
to_char(sample_time,'hh24:mi')='08:54'
order by sample_time desc;


select * from v$active_session_history where sql_id='3tjggpnrjbx7n' order by sample_time desc;
select executions,rows_processed,sysdate from v$sqlstats  where sql_id='82uw4dabjf267';

select PLAN_HASH_VALUE, sn.instance_number,sn.end_interval_time, 
Round(executions_delta) "Execs", s.px_servers_execs_delta, 
Round(elapsed_time_delta/decode(executions_delta,0,1,executions_delta)/1000000/60,2) "mins  per exec",
Round(BUFFER_GETS_DELTA/decode(executions_delta,0,1,executions_delta)) "buffer gets per exec", 
s.rows_processed_delta
from kering_prsieb8_main.dba_hist_sqlstat s join kering_prsieb8_main.dba_hist_snapshot sn on sn.snap_id=s.snap_id and s.instance_number=sn.instance_number  
where sql_id='b0twtfspf91aj' 
--and plan_hash_value=2848875092
--and plan_hash_value=1834285197 
--and plan_hash_value=677306319
--and plan_hash_value=734780486
order by sn.end_interval_time desc, instance_number;

--SQL stats from 2-node RAC
with st as 
(
select s.plan_hash_value, sn.instance_number,trunc(sn.end_interval_time,'MI') end_interval_time, Round(Sum(executions_delta),2) "Execs", decode(SUM(executions_delta),0,null,
Round(SUM(elapsed_time_delta)/SUM(executions_delta)/1000000,8)) "sec  per exec",
decode(SUM(executions_delta),0,null,Round(SUM(BUFFER_GETS_DELTA)/SUM(executions_delta))) "buffer gets per exec", SUM(s.rows_processed_delta) rows_processed_delta
from dba_hist_sqlstat s join dba_hist_snapshot sn on sn.snap_id=s.snap_id and s.instance_number=sn.instance_number  
where sql_id='0npdsp5r9c7yv' 
group by s.plan_hash_value, sn.instance_number,sn.end_interval_time
order by sn.end_interval_time desc, sn.instance_number
)
SELECT nvl(i1.plan_hash_value,i2.plan_hash_value) plan_hash_value, nvl(i1.end_interval_time,i2.end_interval_time) end_interval_time, i1."Execs" "Execs - 1", i2."Execs" "Execs - 2", i1."sec  per exec" "sec  per exec - 1", 
i2."sec  per exec" "sec  per exec - 2",
i1.rows_processed_delta "rows -1",
i2.rows_processed_delta "rows -2",
i1."buffer gets per exec" "buffers per exec -1",
i2."buffer gets per exec" "buffers per exec -2"
from
(select * from st where instance_number=1) i1 full outer join
(select * from st where instance_number=2) i2 on i1.end_interval_time=i2.end_interval_time and i1.plan_hash_value=i2.plan_hash_value
order by end_interval_time desc;

select st.inst_id, st.plan_hash_value, sa.first_load_time, st.last_active_time, st.parse_calls, st.executions,st.rows_processed,
st.buffer_gets 
from gv$sqlstats st 
left join gv$sqlarea sa on sa.sqL_id=st.sql_id and sa.plan_hash_value=st.plan_hash_value and st.inst_id=sa.inst_id
where st.sqL_id='0npdsp5r9c7yv';


--SQL stats for different execution plans for last 24 hours
select PLAN_HASH_VALUE, sn.instance_number, Sum(Round(executions_delta)) "Execs", decode(Sum(executions_delta),0,null,Round(Sum(elapsed_time_delta)/Sum(executions_delta)/1000,2)) "msec  per exec",
decode(Sum(executions_delta),0,null,Round(Sum(BUFFER_GETS_DELTA)/Sum(executions_delta))) "buffer gets per exec", Sum(s.rows_processed_delta)
from dba_hist_sqlstat s join dba_hist_snapshot sn on sn.snap_id=s.snap_id and s.instance_number=sn.instance_number  
where sql_id='6agkk6ykrym6w' 
and sn.end_interval_time>sysdate -1 
group by PLAN_HASH_VALUE, sn.instance_number
order by instance_number, "msec  per exec";

--Sum by day (total for all plans)
select sn.instance_number,trunc(sn.end_interval_time), Sum(Round(executions_delta,2)) "Execs", 
decode(Sum(executions_delta),0,null,Round(Sum(elapsed_time_delta)/Sum(executions_delta)/1000000,2)) "sec  per exec",
decode(sum(executions_delta),0,null,Round(sum(BUFFER_GETS_DELTA)/sum(executions_delta))) "buffer gets per exec", 
Round(sum(s.rows_processed_delta)/Sum(Round(executions_delta,2)),1) "Rows processed per exec"
from dba_hist_sqlstat s join dba_hist_snapshot sn on sn.snap_id=s.snap_id and s.instance_number=sn.instance_number  
where sql_id='56yznta79yk74' 
group by sn.instance_number,trunc(sn.end_interval_time)
order by trunc(sn.end_interval_time) desc;

select * from v$sqlstats where sql_id='7j2wff59pmutj';

desc dba_hist_sqlstat

select * from dba_indexes where index_name='USH_LIMITER';
select bytes/3240008283 from dba_segments where segment_name='USH_LIMITER';

select * from dba_hist_sqltext where sql_id='bh6cpqptrpsf2';

select * from V$SQL_SHARED_CURSOR where sql_id ='f00pvqz6yw7xk';

select * from dba_objects where object_name='ACNT_LOG_SEQ';


select * from V$CLIENT_RESULT_CACHE_STATS;
show parameter result_cache

select * from dba_objects where object_name like 'V$%SQL%';

SELECT * FROM V$INSTANCE;

--Recently modified objects
select owner,object_name,object_type, last_ddl_time 
from dba_objects 
where object_Type<>'JOB' 
order by last_ddl_time desc nulls last; 

select * from V$SQL_SHARED_CURSOR where sql_id in ('68aj8s5dgbdu7');

select sql_id,child_number, executions,parse_calls,loads,invalidations
from v$sql s where sql_id='f5qdqupa8624c';

select value from v$parameter where name='_optimizer_invalidation_period';

select * from v$sqlstats where sql_id='86vmbjtd4rcuq';

--check for recently gathered statistics as a cause of invalidations
--Table/partition stats
select owner,table_name,last_analyzed,global_stats from dba_tab_statistics
--where  last_analyzed > sysdate-6/24 --see Note 557661.1 where 5-hours "invalidation window" is described as a part of Rolling Cursor Invalidation algorithm.
--and 
--table_name='S_CONTACT'
order by last_analyzed desc nulls last;

--Partition stats
select TABLE_OWNER,table_name,partition_name, last_analyzed,global_stats from dba_tab_partitions 
where 
last_analyzed > sysdate-6/24 --see Note 557661.1 where 5-hours "invalidation window" is described as a part of Rolling Cursor Invalidation algorithm.
--and 
--table_name='S_CONTACT'
order by last_analyzed desc nulls last;

--Column stats
select owner,table_name,column_name,last_analyzed, global_stats,user_stats,histogram from dba_tab_columns
where last_analyzed > sysdate-6/24 --between to_date('22.09.15 15:10','dd.mm.yy hh24:mi') and to_date('22.09.15 15:15','dd.mm.yy hh24:mi') --see Note 557661.1 where 5-hours "invalidation window" is described as a part of Rolling Cursor Invalidation algorithm.
-- table_name='S_CONTACT'
order by last_analyzed desc nulls last; 
--Index stats
select owner,index_name,index_type,table_owner,table_name,table_type,uniqueness, last_analyzed 
from dba_indexes 
where last_analyzed > sysdate-6/24 --between to_date('22.09.15 15:10','dd.mm.yy hh24:mi') and to_date('22.09.15 15:15','dd.mm.yy hh24:mi')----see Note 557661.1 where 5-hours "invalidation window" is described as a part of Rolling Cursor Invalidation algorithm.
--and table_name='S_CONTACT'
order by last_analyzed desc nulls last;

select sql_id, sql_text from v$sql where sql_id in ('bu9gygb4cd1vw',
'40h683zy3vr72',
'gm63k2tgb27kc',
'6pr8hm651vq5h');
select * from dba_sequences where SEQUENCE_NAME like 'SEQ_APP_%' order by CACHE_SIZE, last_number desc, sequence_name;
--Last Grant/Revoke commands
select * from dba_audit_trail where action_name like '%GRANT%' order by timestamp desc;

create table ASH_EKSMB20150212 as select * from gv$active_session_history@klyazma_eksmb1 ash
WHERE ASH.SAMPLE_TIME between to_date('12.02.2015 11:15:00','dd.mm.yyyy hh24:mi:ss') and to_date('12.02.2015 11:30:00','dd.mm.yyyy hh24:mi:ss');

select sample_time, session_id,sqL_id,sql_opname,top_level_sql_id,sql_exec_start,wait_class, event,p1,p2,p3,wait_time,session_state,program,module,delta_read_io_bytes,delta_write_io_bytes,delta_interconnect_io_bytes,temp_space_allocated from v$active_session_history ash 
where ASH.SAMPLE_TIME between to_date('22.05.2015 23:10:00','dd.mm.yyyy hh24:mi:ss') and to_date('22.05.2015 23:11:55','dd.mm.yyyy hh24:mi:ss') 
--and session_Id=2983
and sql_opname='CREATE INDEX'
order by ASH.SAMPLE_TIME;
select max(sql_id),sum(physical_read_bytes), force_matching_signature from v$sql_monitor 
where status='EXECUTING'
group by force_matching_signature
order by sum(physical_read_bytes) desc;

-- By waitclass
SELECT 
  TO_CHAR(SES.SAMPLE_TIME,'yyyy-mm-dd') "Sample date",
  TO_CHAR(SES.SAMPLE_TIME,'hh24:mi:ss') "Sample time",
  COUNT(*) "Total",
  COUNT(distinct sample_id) "Number of snapshots",
  COUNT(DECODE(SES.session_State,'ON CPU',1)) "On CPU",
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
  ASH_dbdpc_210210141842 SES
WHERE --SES.SESSION_STATE='WAITING'
  --and SES.SAMPLE_TIME>sysdate-1/24/60
  SES.SAMPLE_TIME between to_date('10.02.2021 14:15:30','dd.mm.yyyy hh24:mi:ss') and to_date('10.02.2021 14:17:30','dd.mm.yyyy hh24:mi:ss')
GROUP BY 
  TO_CHAR(SES.SAMPLE_TIME,'yyyy-mm-dd'),
  TO_CHAR(SES.SAMPLE_TIME,'hh24:mi:ss')
ORDER BY 
  TO_CHAR(SES.SAMPLE_TIME,'hh24:mi:ss');
--  COUNT(*) DESC;

select module, action, count(*) from v$session where program like 'sqlplus%' and status='ACTIVE' group by module, action;

-- By waitclass - compare 2 dates
with day1 as
(
SELECT 
  TO_CHAR(SES.SAMPLE_TIME,'yyyy-mm-dd') "Sample date",
  TO_CHAR(SES.SAMPLE_TIME,'hh24:mi') "Sample time",
  COUNT(distinct sample_id) "Number of snapshots",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Administrative',1))/COUNT(distinct sample_id)) "Administrative",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Application',1))/COUNT(distinct sample_id)) "Application",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Cluster',1))/COUNT(distinct sample_id)) "Cluster",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Commit',1))/COUNT(distinct sample_id)) "Commit",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Concurrency',1))/COUNT(distinct sample_id)) "Concurrency",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Configuration',1))/COUNT(distinct sample_id)) "Configuration",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Network',1))/COUNT(distinct sample_id)) "Network",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Other',1))/COUNT(distinct sample_id)) "Other",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Scheduler',1))/COUNT(distinct sample_id)) "Scheduler",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'System I/O',1))/COUNT(distinct sample_id)) "System I/O",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'User I/O',1))/COUNT(distinct sample_id)) "User I/O"
FROM 
  DBA_HIST_ACTIVE_SESS_HISTORY SES
  --V$ACTIVE_SESSION_HISTORY SES
WHERE --SES.SESSION_STATE='WAITING'
  --and SES.SAMPLE_TIME>sysdate-1/24/60
  SES.SAMPLE_TIME between to_date('08.11.2015 08:00:00','dd.mm.yyyy hh24:mi:ss') and to_date('08.11.2015 10:30:00','dd.mm.yyyy hh24:mi:ss')
  --and sqL_id='bh6cpqptrpsf2'
GROUP BY 
  TO_CHAR(SES.SAMPLE_TIME,'yyyy-mm-dd'),
  TO_CHAR(SES.SAMPLE_TIME,'hh24:mi')
),
day2 as
(
SELECT 
  TO_CHAR(SES.SAMPLE_TIME,'yyyy-mm-dd') "Sample date",
  TO_CHAR(SES.SAMPLE_TIME,'hh24:mi') "Sample time",
  COUNT(distinct sample_id) "Number of snapshots",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Administrative',1))/COUNT(distinct sample_id)) "Administrative",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Application',1))/COUNT(distinct sample_id)) "Application",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Cluster',1))/COUNT(distinct sample_id)) "Cluster",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Commit',1))/COUNT(distinct sample_id)) "Commit",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Concurrency',1))/COUNT(distinct sample_id)) "Concurrency",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Configuration',1))/COUNT(distinct sample_id)) "Configuration",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Network',1))/COUNT(distinct sample_id)) "Network",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Other',1))/COUNT(distinct sample_id)) "Other",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'Scheduler',1))/COUNT(distinct sample_id)) "Scheduler",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'System I/O',1))/COUNT(distinct sample_id)) "System I/O",
  Round(COUNT(DECODE(SES.WAIT_CLASS,'User I/O',1))/COUNT(distinct sample_id)) "User I/O"
FROM 
  DBA_HIST_ACTIVE_SESS_HISTORY SES
  --V$ACTIVE_SESSION_HISTORY SES
WHERE --SES.SESSION_STATE='WAITING'
  --and SES.SAMPLE_TIME>sysdate-1/24/60
  SES.SAMPLE_TIME between to_date('15.11.2015 08:00:00','dd.mm.yyyy hh24:mi:ss') and to_date('15.11.2015 10:30:00','dd.mm.yyyy hh24:mi:ss')
  --and sqL_id='bh6cpqptrpsf2'
GROUP BY 
  TO_CHAR(SES.SAMPLE_TIME,'yyyy-mm-dd'),
  TO_CHAR(SES.SAMPLE_TIME,'hh24:mi')
)
select NVL(day1."Sample time",day2."Sample time") "Sample time",
day1."Number of snapshots" "day1 Number of snapshots",
day2."Number of snapshots" "day2 Number of snapshots",
day1."Administrative" "day1 Administrative",
day2."Administrative" "day2 Administrative",
day1."Application" "day1 Application",
day2."Application" "day2 Application",
day1."Cluster" "day1 Cluster",
day2."Cluster" "day2 Cluster",
day1."Commit" "day1 Commit",
day2."Commit" "day2 Commit",
day1."Concurrency" "day1 Concurrency",
day2."Concurrency" "day2 Concurrency",
day1."Configuration" "day1 Configuration",
day2."Configuration" "day2 Configuration",
day1."Network" "day1 Network",
day2."Network" "day2 Network",
day1."Other" "day1 Other",
day2."Other" "day2 Other",
day1."Scheduler" "day1 Scheduler",
day2."Scheduler" "day2 Scheduler",
day1."System I/O" "day1 System I/O",
day2."System I/O" "day2 System I/O",
day1."User I/O" "day1 User I/O",
day2."User I/O" "day2 User I/O"
from day1 full outer join day2 on day1."Sample time"=day2."Sample time"
ORDER BY 
  NVL(day1."Sample time",day2."Sample time");

SELECT * FROM V$ACTIVE_SESSION_HISTORY WHERE TO_CHAR(SAMPLE_TIME,'dd.mm.yyyy hh24:mi')='24.11.2014 19:30' order by sample_id;
SELECT * FROM V$ACTIVE_SESSION_HISTORY WHERE TO_CHAR(SAMPLE_TIME,'dd.mm.yyyy hh24:mi:ss')='21.09.2014 00:12:48';
SELECT * FROM V$ACTIVE_SESSION_HISTORY WHERE TO_CHAR(SAMPLE_TIME,'dd.mm.yyyy hh24:mi:ss')='21.09.2014 00:12:49';

SELECT * FROM V$ACTIVE_SESSION_HISTORY WHERE event='cursor: pin S wait on X';
SELECT * FROM V$ACTIVE_SESSION_HISTORY WHERE SESSION_ID='12500' and sql_id<>'6dcgjdnr7nzkh';
SELECT sample_time,event,sqL_id,top_level_sql_id FROM V$ACTIVE_SESSION_HISTORY WHERE 
sample_Time>sysdate-1/24;-- and SESSION_ID='7836';

SELECT * FROM V$ACTIVE_SESSION_HISTORY WHERE sql_id='0wut7wt3j496f' and in_parse='Y' and event is null;
SELECT * FROM V$ACTIVE_SESSION_HISTORY WHERE sql_id='6gtqnttp49q52';

SELECT FORCE_MATCHING_SIGNATURE, count(*) 
FROM V$ACTIVE_SESSION_HISTORY WHERE 
--event='direct path read'
 sample_time>sysdate-1/24/60*30 --!!Last 30 minutes
group by FORCE_MATCHING_SIGNATURE
order by count(*) desc;


select trunc(s.end_interval_time) "Date", p.sqL_id,p.plan_hash_value,
avg(p.optimizer_cost) optimizer_cost,
max(p.loaded_versions) loaded_versions,
Round(sum(executions_delta)/1000) "Executions,10*3",
decode(Sum(executions_delta),0,null,Round(Sum(elapsed_time_delta)/Sum(executions_delta)/1000000,4)) "Elapsed time per exec, sec",
decode(Sum(executions_delta),0,null,Round(Sum(CPU_TIME_DELTA)/Sum(executions_delta)/1000000,4)) "Elapsed time per exec, sec",
sum(Invalidations_delta) "Invalidations",
Sum(Parse_calls_delta) "Parse calls",
Round(Sum(Disk_reads_delta)/1000000) "Disk reads, mln",
decode(Sum(executions_delta),0,null,Round(Sum(buffer_gets_delta)/Sum(executions_delta))) "Buffer gets per exec",
Round(Sum(rows_processed_delta)/1000000) "Rows processed, mln",
Round(Sum(Physical_read_bytes_delta)/1024/1024/1024) "Physical read, Gb",
Round(Sum(Physical_read_requests_delta)/1000000) "Physical read requests, mln"
from dba_hist_sqlstat p
join dba_hist_snapshot s on s.snap_id=p.snap_id
where p.plan_hash_value=2844419022
group by trunc(s.end_interval_time) , p.sqL_id,p.plan_hash_value
order by trunc(s.end_interval_time);

select s.sql_id, count(distinct ash.session_Id),Round(sum(ash.delta_read_io_bytes)/1024/1024/1024,1) "Read,Gb", s.sql_text
from v$active_session_history ash
left join v$sqlstats s on s.sql_id=ash.sql_id
where ash.sql_plan_hash_value=2844419022
and ash.sample_time >sysdate-1/24/60*45 --!!Last 45 minutes
group by s.sql_id,s.sql_text
order by "Read,Gb" desc;

select sql_id, sum(executions) "Executions", ROund(sum(elapsed_time)/1000000/60) "Elapsed,min", round(sum(user_io_wait_time)/1000000/60) "User IO waits, min" 
from v$sqlstats where plan_hash_value=2844419022
group by sql_id
order by sum(elapsed_time)/1000000/60 desc;

select s.sql_id, count(distinct ash.session_Id),Round(sum(ash.delta_read_io_bytes)/1024/1024/1024,1) "Read,Gb", ash.current_obj#, d.object_name,d.subobject_name,s.sql_text
from v$active_session_history ash
left join v$sqlstats s on s.sql_id=ash.sql_id
left join dba_objects d on d.object_id=ash.current_obj#
where ash.sql_plan_hash_value=2844419022
and ash.sample_time >sysdate-1/24/60*145 --!!Last 45 minutes
group by s.sql_id,ash.current_obj#, d.object_name,d.subobject_name,s.sql_text
order by "Read,Gb" desc;

SELECT * FROM gV$ACTIVE_SESSION_HISTORY WHERE program like  '%J%' and sql_id<>'6dcgjdnr7nzkh';
select * from v$cursor_cache;
select * from v$session_longops where opname like '%Gather%';
select * from gv$active_session_history where session_id='23279';
--sessions which collect stats
select ash.* from v$sql s join gv$active_session_history ash on ash.sql_id=s.sql_id where s.sql_text like '%stats%';

select * from v$sql_shared_cursor where sql_id='a523tr4d6a36t' and  roll_invalid_mismatch='Y';  

select sql_id, first_load_time, object_status, count(*) from v$sql 
where sql_id = 'a523tr4d6a36t' 
group by sql_id, first_load_time,object_status
order by first_load_time,object_status;


select * from v$OPEN_CURSOR where sql_id='a523tr4d6a36t';
select count(*) from dba_objects  where status='INVALID';

select * from dba_objects where object_name like '%CURSOR%';

select * from dba_objects 
where object_name='EVENT_LOG'
order by last_ddl_time desc nulls last;
-- 

--2-level Blocking tree from v$ASH
SELECT a.sample_time, a.session_id waiter_session_id, A.sql_id waiter_sql_id,a.event waiter_event, b.session_id "blocker sid", b.session_serial# "blocking serial#", b.inst_id "blocker inst_id", b.sql_id "blocker sql_id",b.event "blocker event" 
, c.session_id "blocker sid", c.session_serial# "blocking serial#", c.inst_id "blocker inst_id", c.sql_id "blocker sql_id",c.event "blocker event2" 
, d.session_id "blocker sid", d.session_serial# "blocking serial#", d.inst_id "blocker inst_id", d.sql_id "blocker sql_id",d.event "blocker event3" 
FROM mbazgutdinov.ASH_ERMB_210212175551 A 
LEFT JOIN mbazgutdinov.ASH_ERMB_210212175551 B ON A.BLOCKING_SESSION=B.SESSION_ID AND A.BLOCKING_SESSION_SERIAL#=B.SESSION_SERIAL# and a.BLOCKING_INST_ID =b.inst_id and a.sample_time=b.sample_time
LEFT JOIN mbazgutdinov.ASH_ERMB_210212175551 C ON B.BLOCKING_SESSION=C.SESSION_ID AND B.BLOCKING_SESSION_SERIAL#=C.SESSION_SERIAL# and B.BLOCKING_INST_ID =C.inst_id and b.sample_time=c.sample_time
LEFT JOIN mbazgutdinov.ASH_ERMB_210212175551 D ON C.BLOCKING_SESSION=D.SESSION_ID AND C.BLOCKING_SESSION_SERIAL#=D.SESSION_SERIAL# and C.BLOCKING_INST_ID =D.inst_id and C.sample_time=D.sample_time
WHERE a.SAMPLE_TIME BETWEEN TO_DATE('12/02/2021 16:43:16','dd/mm/yyyy hh24:mi:ss') AND TO_DATE('12/02/2021 16:43:30','dd/mm/yyyy hh24:mi:ss')
AND nvl(A.event,'1')!='log file sync'
order by a.SAMPLE_TIME,b.session_id;



-- Top 5 WAIT events 
with
ASH as
(
SELECT /* +MATERIALIZE */
  SES.SAMPLE_TIME,
  SES.EVENT,
  COUNT(*) count_ses,
  RANK() OVER (PARTITION BY SES.SAMPLE_TIME ORDER BY COUNT(*) DESC) RANK 
FROM 
--DBA_HIST_ACTIVE_SESS_HISTORY SES
v$active_session_history ses
WHERE 
--  ses.snap_id between 58030 and 58034
  --SES.SAMPLE_TIME BETWEEN TO_DATE('22.07.2014 01:10','dd.mm.yyyy hh24:mi') AND TO_DATE('22.07.2014 01:15','dd.mm.yyyy hh24:mi')
  --and ses.INSTANCE_NUMBER=1
  --and ses.dbid=(select dbid from v$database)
 SESSION_STATE='WAITING'
group by SES.SAMPLE_TIME,event
order by SES.SAMPLE_TIME, COUNT(*) desc
)
select 
      TO_DATE(TO_CHAR(ASH1.SAMPLE_TIME,'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss') "Sample time", 
      to_char(ASH1.SAMPLE_TIME,'hh24:mi:ss') "Time",
      ASH1.EVENT "Top1 event",  
      ASH1.COUNT_SES "Top1 count sess",
      ASH2.EVENT "Top2 event",  
      ASH2.COUNT_SES "Top2 count sess", 
      ASH3.EVENT "Top3 event",  
      ASH3.COUNT_SES "Top3 count sess", 
      ASH4.EVENT "Top4 event",  
      ASH4.COUNT_SES "Top4 count sess", 
      ASH5.EVENT "Top5 event",  
      ASH5.COUNT_SES "Top5 count sess"
from (select * from ASH where RANK=1) ASH1 
LEFT JOIN (SELECT * FROM ASH WHERE RANK=2) ASH2 ON ASH1.SAMPLE_TIME=ASH2.SAMPLE_TIME
LEFT JOIN (SELECT * FROM ASH WHERE RANK=3) ASH3 ON ASH1.SAMPLE_TIME=ASH3.SAMPLE_TIME
LEFT JOIN (SELECT * FROM ASH WHERE RANK=4) ASH4 ON ASH1.SAMPLE_TIME=ASH4.SAMPLE_TIME
LEFT JOIN (SELECT * FROM ASH WHERE RANK=5) ASH5 ON ASH1.SAMPLE_TIME=ASH5.SAMPLE_TIME
ORDER BY ASH1.SAMPLE_TIME desc;


-- All waiting sessions 
SELECT 
SES.SAMPLE_TIME,
 SES.INSTANCE_NUMBER,
  SES.BLOCKING_SESSION,
  max(sessioN_id) "One of waiting sessions",
  SES.BLOCKING_SESSION_STATUS,
  ses.event,
  ses.wait_class,
  ses.CURRENT_OBJ#,
  ses.sql_id,
  (select sql_text from v$sqlstats s where s.sql_id=ses.sql_id) "SQL Text",
  plsql_object_id,
  plsql_subprogram_id,
  plsql_entry_object_id,
  plsql_entry_subprogram_id,
  count(*)
from 
DBA_HIST_ACTIVE_SESS_HISTORY SES
WHERE 
  --SES.SNAP_ID=58033
  SES.SAMPLE_TIME between to_date('13.06.2016 03:29:00','dd.mm.yyyy hh24:mi:ss') and to_date('13.06.2016 03:32:18','dd.mm.yyyy hh24:mi:ss')
 -- and ses.INSTANCE_NUMBER=1
--  and ses.snap_id between 62680 and 62691
  and ses.dbid=(select dbid from v$database)
 -- and current_obj#=53365
--  and ses.sample_time=(select min(sample_time) from DBA_HIST_ACTIVE_SESS_HISTORY ses2
--                       where 
--                       SES2.SNAP_ID=58033
--                        and ses2.INSTANCE_NUMBER=1
--                       and ses2.dbid=(select dbid from v$database)
--                      )
and ses.event='log file switch completion'
GROUP BY 
SES.SAMPLE_TIME,
  SES.BLOCKING_SESSION,
  SES.BLOCKING_SESSION_STATUS,
  ses.event,
  ses.wait_class,
  SES.CURRENT_OBJ#,
  plsql_object_id,
  plsql_subprogram_id,
  plsql_entry_object_id,
  plsql_entry_subprogram_id,
  ses.sql_id,
  ses.instance_number
ORDER BY SES.SAMPLE_TIME,COUNT(*) DESC;

select * from V$ACTIVE_SESSION_HISTORY where sql_id='brb1ww6a3qp01' and SAMPLE_TIME between to_date('13.06.2016 03:24:00','dd.mm.yyyy hh24:mi:ss') and to_date('13.06.2016 03:32:18','dd.mm.yyyy hh24:mi:ss')  order by sample_time desc;

select *
--SES.SAMPLE_TIME, BLOCKING_SESSION,COUNT(*)
from 
  DBA_HIST_ACTIVE_SESS_HISTORY SES
WHERE 
  --SES.SNAP_ID=58033
  --SES.SAMPLE_TIME between to_date('28.10.2015 10:45:00','dd.mm.yyyy hh24:mi:ss') and to_date('28.10.2015 11:59:18','dd.mm.yyyy hh24:mi:ss')
  --TO_CHAR(SES.SAMPLE_TIME,'YYYY.MM.DD HH24:MI:SS') > '2015.11.14 04:15:00'
   ses.INSTANCE_NUMBER=1
  and ses.snap_id between 86280 and 86301
  and ses.dbid=(select dbid from v$database)
  and sql_id='53xh39bna62n9'
--  and event='cursor: pin S wait on X'
and session_id=314
--and session_serial#=63103
--and current_obj#=53365
--group by SES.SAMPLE_TIME, BLOCKING_SESSION
order by sample_time;

select * from dba_objects where object_id in (158855,
16079,
16338,
16079,
16079,
190024);

Z#IX_Z#SUM_DOG_COLL		16079	268592	INDEX
Z#IX_Z#MAIN_DOCUM_REF_COLL		16338	267737	INDEX
Z#BC_OPER_CARD_PAR		158855	259747	TABLE
IDX_Z#BC_OPER_CARD_PAR_DOC		190024	259756	INDEX

select * from v$sqlstats where sql_id='3d1q1z0ftnuqf';

select * from dba_hist_sqlstat where sql_id='53xh39bna62n9';
  select * from dba_hist_sqltext where sql_id='53xh39bna62n9';
select * from dba_objects where object_id='53365';

select * from dba_indexes where table_name='DEALPASSPORT';

EXEC DBMS_STATS.GATHER_SCHEMA_STATS(OWNNAME=>'SQLTXPLAIN',OPTIONS=>'LIST STALE');
select * from DBA_TAB_MODIFICATIONS WHERE TABLE_OWNER='SQLTXPLAIN';
SELECT * FROM DBA_HIST_ACTIVE_SESS_HISTORY SES
WHERE --SES.SAMPLE_TIME BETWEEN TO_DATE('22.07.2014 01:10','dd.mm.yyyy hh24:mi') AND TO_DATE('22.07.2014 01:15','dd.mm.yyyy hh24:mi')
--and sql_opname<>'SELECT'
sql_id='bqpsd0vubuytn'
order by SES.SAMPLE_TIME desc nulls last;



-- All waiting sessions 
SELECT 
  ses.event,
  ses.wait_class,
  ses.in_parse,
  ses.sql_id,
  plsql_entry_object_id,
  plsql_entry_subprogram_id,
  count(distinct session_id) "Sessions affected",
  round(sum(time_waited)/1000000) "Total time waited, sec"
from 
  DBA_HIST_ACTIVE_SESS_HISTORY SES
WHERE 
  SES.SNAP_ID IN (58032,58033,58034)
  and ses.INSTANCE_NUMBER=1
  and ses.dbid=(select dbid from v$database)
--and ses.wait_class='Concurrency'
  and ses.event in ('cursor: pin S wait on X','cursor: mutex S','cursor: mutex X','cursor: pin S','cursor: pin X')
GROUP BY 
  ses.event,
  ses.wait_class,
  ses.in_parse,
  plsql_entry_object_id,
  plsql_entry_subprogram_id,
  ses.sql_id
ORder by sum(time_waited) desc, count(distinct session_id) desc;


-- All session in PL/SQL Compilation / Hard parse
SELECT 
  *
from 
  DBA_HIST_ACTIVE_SESS_HISTORY SES
WHERE 
   SES.SNAP_ID between 58030 and 58034
  and ses.INSTANCE_NUMBER=1
  and ses.dbid=(select dbid from v$database)
  --and in_plsql_compilation='Y'
  and in_hard_parse='Y'
order by SES.SNAP_ID, sample_time;


-- 
SELECT 
  *
from 
  DBA_HIST_ACTIVE_SESS_HISTORY SES
WHERE 
   SES.SNAP_ID between 58030 and 58034
  and ses.INSTANCE_NUMBER=1
  and ses.dbid=(select dbid from v$database)
and session_id=12205
order by SES.SNAP_ID, sample_time;




select owner,object_type,object_name,procedure_name
from dba_procedures 
where object_id=65728
and subprogram_id=106;

select owner,object_type,object_name,procedure_name
from dba_procedures 
where object_id=65694
and subprogram_id=48;

select OWNER,object_id, object_type,object_name, last_ddl_time from dba_objects 
where owner='XBANK_ZUB' 
and object_name='DPS_REP_DAYS';

select OWNER,object_id, object_type,object_name, last_ddl_time from dba_objects 
where object_name='ADMIN_CORE';


SELECT 
  current_obj#,in_parse,
  blocking_session,
  event,
  sql_id,
  ses.*
from 
DBA_HIST_ACTIVE_SESS_HISTORY SES
WHERE 
  SES.SNAP_ID IN (58030, 58031, 58032)
  and ses.INSTANCE_NUMBER=1
  and ses.dbid=(select dbid from v$database)
  and to_char(ses.sample_time,'dd.mm.yyyy hh24:mi')='09.07.2014 08:00'
--  ses.sample_time=(select max(sample_time) from DBA_HIST_ACTIVE_SESS_HISTORY ses2
--                       where 
--                        SES2.SNAP_ID=58031
--                        and ses2.INSTANCE_NUMBER=1
--                        and ses2.dbid=(select dbid from v$database)
--                      )  
--and event='cursor: pin S wait on X'
And (session_id =12205 and blocking_session=6001
      or session_id =6001 and blocking_session=12205)
order by ses.sample_time, seq# 
                      ;

SELECT 
  current_obj#,
  in_parse,
  blocking_session,
  event,
  plsql_entry_object_id,
  plsql_entry_subprogram_id,
  ses.*
from 
DBA_HIST_ACTIVE_SESS_HISTORY SES
WHERE 
  SES.SNAP_ID=58033
  and ses.INSTANCE_NUMBER=1
  and ses.dbid=(select dbid from v$database)
and ses.sample_time=(select min(sample_time) from DBA_HIST_ACTIVE_SESS_HISTORY ses2
                       where 
                        SES2.SNAP_ID=58033
                        and ses2.INSTANCE_NUMBER=1
                        and ses2.dbid=(select dbid from v$database)
                      )  
  and session_id=14727;
select * from v$session where sid=5017;
select * from v$active_session_history where session_id=5017 order by sample_time desc;
select latch#,name from v$latchname where latch#=135;

select * from v$sql_monitor;  
select * from v$sql_shared_cursor where sql_id='fr1z356d8728s';  
select * from v$sqlarea where sql_id IN ('2qsbg0n3jw29d','1kvkt4rj8hf4v','85yxvu2u7525x','3t274vts3h4as');
select * from v$sqlarea where upper(SQL_TEXT) like '%COMPILE%';
  select * from dba_objects

select * from DBA_HIST_SYSTEM_EVENT;
select * from dba_objects where object_name like 'DBA_HIST%SQL%';

select * from v$parameter where name like '%sharin%';

select * from v$version;
select * from registry$history;

select * from DBA_HIST_SQLSTAT
where sql_id='4zy6sd03t2vam'
order by snap_id desc;

select * from DBA_HIST_SQLTEXT
where upper(SQL_TEXT) like '%DPS_REP_DAYS%';

select * from DBA_HIST_SQLTEXT
where sql_id in ('9k26umgptg7x8','9k26umgtg7x8');--,'85yxvu2u7525x','4hkz5ttgatu3g');--='8z7sw0vtd102k';-- in ('4vs91dcv7u1p6','55ramhgr3xstz','78s98xt4tzynw','8sjskw1496nn8','68rgb1bycz5yk','9agmjjr3gzhta','9bb8jk0v91xv4');

select * from DBA_HIST_SQL_PLAN
where sql_id like '3t274vts3h4as%';

select * from DBA_HIST_LATCH_MISSES_SUMMARY
where snap_id=58033
order by wtr_slp_count desc;


select MIN(startup_time) "Instance startup time", MIN(START_TIME) "First SGA Resize", MAX(END_TIME) "Last SGA Resize" from v$sga_resize_ops join v$instance on 1=1;

select count(*),sql_id,count(distinct session_id) from v$active_session_history
where event='db file sequential read'
group by sql_id
order by count(*) desc;

select count(*) from v$session;

select owner,object_type,object_name,procedure_name
from dba_procedures 
where object_id=65694
and subprogram_id=60;

select * from dba_objects where object_name='CLIENT_CORE';

select sample_Time, program, wait_class, sql_id,count(*), count(distinct session_id)
from v$active_session_history 
where SAMPLE_TIME BETWEEN TO_DATE('26.02.2015 22:20','dd.mm.yyyy hh24:mi') AND TO_DATE('26.02.2015 22:21','dd.mm.yyyy hh24:mi')
--and program='sqlplus@olova1 (TNS V1-V3)'
group by program,wait_class,sample_Time,sql_id
order by sample_Time desc, count(*) desc;

select * from v$active_session_history;



---From SQL Macro script
-- many filters in WHERE to change
with
ASH as
(
SELECT ASH.SAMPLE_TIME,
  ASH.EVENT,
  ROUND(AVG(ash.TM_DELTA_TIME)/1000000,2) "Time spent,sec",
  COUNT(*) COUNT_SES,
  AVG(decode(ash.time_waited,0,null,ash.time_waited)) avg_time_waited,
  rank() over (partition by ash.SAMPLE_TIME order by count(*) desc, AVG(decode(ash.time_waited,0,null,ash.time_waited)) desc) Rank 
FROM 
--dba_hist_active_sess_history ASH
v$active_session_history ash
WHERE 
1=1
--and SAMPLE_TIME between to_date('23.12.2022 09:00:30','dd.mm.yyyy hh24:mi:ss') and to_date('23.12.2022 14:17:30','dd.mm.yyyy hh24:mi:ss')
	--  SES.SAMPLE_TIME between to_date('21.07.2016 12:00:00','dd.mm.yyyy hh24:mi:ss') and to_date('21.07.2016 14:30:00','dd.mm.yyyy hh24:mi:ss')
--  and snap_id between 98179 and 98193 
--  and ASH.dbid=1303994287
group by ash.SAMPLE_TIME,ash.event 
order by ash.SAMPLE_TIME, COUNT(*) desc
),
ASH_t as
(
SELECT ASH.SAMPLE_TIME,
  COUNT(*) COUNT_SES,
  COUNT(case when event='db file sequential read' then 1 end) COUNT_DBFSR,
  COUNT(case when event='log file sync' then 1 end) COUNT_LFS,
  COUNT(case when event is null then 1 end) COUNT_ON_CPU,
  COUNT(case when wait_class='Concurrency' then 1 end) COUNT_CONCURRENCY,
  COUNT(case when wait_class='Configuration' then 1 end) COUNT_CONFIGURATION,
  COUNT(case when wait_class='Other' then 1 end) COUNT_Other,
  COUNT(case when wait_class='Network' then 1 end) COUNT_NETWORK,
  COUNT(case when wait_class='Application' then 1 end) COUNT_Application,
  COUNT(case when IN_HARD_PARSE='Y' then 1 end) COUNT_IN_HARD_PARSE,
  COUNT(case when IN_PARSE='Y' then 1 end) COUNT_IN_PARSE,
  COUNT(case when event='latch free' then 1 end) count_latch_free,
  COUNT(case when event='latch free' and P2=467 then 1 end) count_latch_free_467,
  COUNT(case when event='latch free' and P2=616 then 1 end) count_latch_free_616,
  COUNT(case when event='latch: call allocation' then 1 end) count_latch_call_allocation,
  COUNT(case when event='library cache: mutex X' then 1 end) count_library_cache_mutex_X,
  COUNT(case when event='enq: DX contention' then 1 end) count_enq_DX_contention,
  COUNT(case when event='latch: shared pool' then 1 end) count_latch_shared_pool,  
  COUNT(case when event='enq: TX - index contention' then 1 end) count_enq_TX_index_contention,
  COUNT(case when event='row cache mutex' then 1 end) count_row_cache_mutex,  
  COUNT(case when event='enq: SQ - contention' then 1 end) count_enq_SQ_contention,  
  COUNT(case when action like 'ORA$AT_OS_OPT_SY%' then 1 end) count_gather_stats_sessions,  
  Round(SUM(case when action like 'ORA$AT_OS_OPT_SY%' then DELTA_READ_IO_BYTES end)/1024/1024) "dbms_stats read, MB",
  AVG(case when event='db file sequential read' then decode(time_waited,0,null,time_waited) end) avg_time_waited_DBFSR, 
  AVG(case when event='log file sync' then decode(time_waited,0,null,time_waited) end) avg_time_waited_LFS, 
  AVG(case when event='log file parallel write' then decode(time_waited,0,null,time_waited) end) avg_time_waited_LFPW, 
  AVG(case when event='LGWR wait for redo copy' then decode(time_waited,0,null,time_waited) end) avg_time_waited_LGWRWFRD, 
--Round(SUM(DELTA_READ_MEM_BYTES)/1024/1024) "Total read from buffer cache, MB",
  Round(SUM(DELTA_READ_IO_BYTES)/1024/1024) "Total read MB",
  Round(SUM(DELTA_WRITE_IO_BYTES)/1024/1024) "Total write MB",
  Round(SUM(case when program like '%(DBW%' then DELTA_WRITE_IO_BYTES end)/1024/1024) "DBWR write MB",
  Round(SUM(DELTA_READ_IO_REQUESTS)) "Total read requests",
  Round(SUM(DELTA_WRITE_IO_REQUESTS)) "Total write requests",
  Round(SUM(case when program like '%(DBW%' then DELTA_WRITE_IO_REQUESTS end)) "DBWR write requests",
  Round(SUM(TEMP_SPACE_ALLOCATED)/1024/1024/1024,1) "TEMP allocation, GB",
  Round(MAX(TEMP_SPACE_ALLOCATED)/1024/1024,1) "Max TEMP allocation per process, MB",
  Round(SUM(PGA_ALLOCATED)/1024/1024/1024,1) "PGA allocation, GB",  
  Round(MAX(PGA_ALLOCATED)/1024/1024,1) "Max PGA allocation per process, MB",
  count(case when force_matching_signature=4479854810611774685 then 1 end) "FMS 4479854810611774685 sessions",
  count(case when force_matching_signature=6199011555372230014 then 1 end) "FMS 6199011555372230014 sessions",
  count(case when force_matching_signature=10602832839598511493 then 1 end) "FMS 10602832839598511493 sessions",
  count(case when force_matching_signature=7722310109089591007 then 1 end) "FMS 7722310109089591007 sessions"
FROM 
--dba_hist_active_sess_history ASH
v$active_session_history ash
WHERE 
1=1
--and SAMPLE_TIME between to_date('23.12.2022 09:00:30','dd.mm.yyyy hh24:mi:ss') and to_date('23.12.2022 14:17:30','dd.mm.yyyy hh24:mi:ss')
	--  SES.SAMPLE_TIME between to_date('21.07.2016 12:00:00','dd.mm.yyyy hh24:mi:ss') and to_date('21.07.2016 14:30:00','dd.mm.yyyy hh24:mi:ss')
--  and snap_id between 98179 and 98193 
--  and ASH.dbid=1303994287
group by ash.SAMPLE_TIME
),
LGW_STAT as 
(
select 
  ASH.SAMPLE_TIME,
  LISTAGG(NVL(EVENT,'ON CPU'),', ') EVENT,
  COUNT(*) "LGWR sessions",
  ROUND(AVG(DELTA_TIME)/1000000,2) "Time spent,sec", 
  AVG(decode(time_waited,0,null,time_waited)) avg_time_waited, 
  Round(SUM(DELTA_READ_IO_BYTES)/1024/1024,2) "Read, Mb",
  Round(SUM(DELTA_WRITE_IO_BYTES)/1024/1024,2) "Written, Mb",
  Round(SUM(DELTA_WRITE_IO_REQUESTS)) "Write requests",
  Round(SUM(DELTA_READ_IO_REQUESTS)) "Read requests"
FROM 
--dba_hist_active_sess_history ASH
v$active_session_history ash
WHERE 
1=1
--and SAMPLE_TIME between to_date('23.12.2022 09:00:30','dd.mm.yyyy hh24:mi:ss') and to_date('23.12.2022 14:17:30','dd.mm.yyyy hh24:mi:ss')
--  and snap_id between 98179 and 98193 
--  and ASH.dbid=1303994287
and program like '%(LG%%' --and (event is null or event='log file parallel write')
group by ASH.SAMPLE_TIME
order by ASH.SAMPLE_TIME, COUNT(*) desc
),
DBW_STAT as 
(
select 
  ASH.SAMPLE_TIME,
  COUNT(*) "Active sess DBWn",
  COUNT(case when event is null then 1 end) "DBW processes on CPU",
  COUNT(case when event='db file parallel write' then 1 end) "DBW processes on db file parallel write",
  COUNT(case when event='db file async I/O submit'  then 1 end) "DBW processes on db file async I/O submit",
  COUNT(case when event='latch: redo writing'   then 1 end) "DBW processes on latch: redo writing",
  ROUND(AVG(DELTA_TIME)/1000000,2) "Time spent,sec", 
  AVG(decode(time_waited,0,null,time_waited)) avg_time_waited, 
  Round(SUM(DELTA_READ_IO_BYTES)/1024/1024,2) "Read, Mb",
  Round(SUM(DELTA_WRITE_IO_BYTES)/1024/1024,2) "Written, Mb",
  Round(SUM(DELTA_WRITE_IO_REQUESTS)) "Write requests",
  Round(SUM(DELTA_READ_IO_REQUESTS)) "Read requests"
FROM 
--dba_hist_active_sess_history ASH
v$active_session_history ash
WHERE 
1=1
--and SAMPLE_TIME between to_date('23.12.2022 09:00:30','dd.mm.yyyy hh24:mi:ss') and to_date('23.12.2022 14:17:30','dd.mm.yyyy hh24:mi:ss')
--  and snap_id between 98179 and 98193 
--  and ASH.dbid=1303994287
and program like '%(DBW%%'
group by ASH.SAMPLE_TIME
order by ASH.SAMPLE_TIME, COUNT(*) desc
)
select 
      TO_DATE(TO_CHAR(ASH_t.SAMPLE_TIME,'dd.mm.yyyy hh24:mi:ss'),'dd.mm.yyyy hh24:mi:ss') "Sample time", 
      TO_CHAR(ASH_t.SAMPLE_TIME,'hh24:mi:ss') "Time", 
      ASH_t.COUNT_SES "Total active sessions",
      ASH_t.COUNT_ON_CPU  "Sessions on CPU",
      ASH_t.COUNT_CONCURRENCY "Sessions on Concurrency",
      ASH_t.COUNT_OTHER "Sessions on Other",
      ASH_t.COUNT_CONFIGURATION "Sessions on Configuration",
      ASH_t.COUNT_NETWORK "Sessions on Network",    
      ASH_t.COUNT_Application "Sessions on Application",
      ASH_t.COUNT_IN_HARD_PARSE "Sessions in Hard parse",
      ASH_t.COUNT_IN_PARSE "Sessions in parse",
      ASH_t.count_latch_free "Sessions on latch free",
      ASH_t.count_latch_free_467 "Sessions on latch free, latch 467",
      ASH_t.count_latch_free_616 "Sessions on latch free, latch 616",
      ASH_t.count_latch_call_allocation "Sessions on latch call allocation",
      ASH_t.count_library_cache_mutex_X "Sessions on library cache mutex X",
      ASH_t.count_enq_DX_contention "Sessions on enq DX contention",
      ASH_t.count_latch_shared_pool "Sessions on latch shared pool",
      ASH_t.count_enq_TX_index_contention "Sessions on enq index contention",
      ASH_t.count_row_cache_mutex "Sessions on row cache mutex",
      ASH_t.count_enq_SQ_contention "Sessions on enq SQ contention",
      ASH_t.COUNT_LFS "Sessions ON log file sync",
      ASH_t.COUNT_DBFSR "Sessions ON db file sequential read",
      ASH_t.count_gather_stats_sessions "Sessions of dbms_stats",
      ASH_t."dbms_stats read, MB" "Read by dbms_stats sessions, MB",
      ASH_t."FMS 4479854810611774685 sessions",
      ASH_t."FMS 6199011555372230014 sessions",
      ASH_t."FMS 10602832839598511493 sessions",
      ASH_t."FMS 7722310109089591007 sessions",
      Round(ASH_t.avg_time_waited_DBFSR/1000,1) "AVG db file sequential read,msec",
      Round(ASH_t.avg_time_waited_LFS/1000,1) "AVG log file sync,msec",
      Round(ASH_t.avg_time_waited_LFPW/1000,1) "AVG log file parallel write,msec",
      Round(ASH_t.avg_time_waited_LGWRWFRD/1000,1) "AVG LGWR wait for redo copy,msec",
      --ASH_t."Total read from buffer cache, MB",
      ASH_t."Total read MB",
      ASH_t."Total write MB",
      ASH_t."DBWR write MB",
      ASH_t."Total read requests",
      ASH_t."Total write requests", 
      ASH_t."DBWR write requests", 
      ASH_t."TEMP allocation, GB", 
      ASH_t."Max TEMP allocation per process, MB",
      ASH_t."PGA allocation, GB", 
      ASH_t."Max PGA allocation per process, MB",
      NVL(ASH1.EVENT,'On CPU') "Top1 event",  
      ASH1.COUNT_SES "Top1 count sess",
      Round(ASH1.avg_time_waited/1000,1) "Top1 event avg wait,msec",
        NVL(ASH2.EVENT,'On CPU') "Top2 event",  
        ASH2.COUNT_SES "Top2 count sess", 
        Round(ASH2.avg_time_waited/1000,1) "Top2 event avg wait,msec",
        NVL(ASH3.EVENT,'On CPU') "Top3 event",  
        ASH3.COUNT_SES "Top3 count sess", 
        Round(ASH3.avg_time_waited/1000,1) "Top3 event avg wait,msec",
        NVL(ASH4.EVENT,'On CPU') "Top4 event",  
        ASH4.COUNT_SES "Top4 count sess", 
        Round(ASH4.avg_time_waited/1000,1) "Top4 event avg wait,msec",
        NVL(ASH5.EVENT,'On CPU') "Top5 event",  
        ASH5.COUNT_SES "Top5 count sess", 
        Round(ASH5.avg_time_waited/1000,1) "Top5 event avg wait,msec", 
      ROUND(LGW_STAT."Written, Mb"/LGW_STAT."Time spent,sec") "Written by LGW, MB/sec",
      ROUND(LGW_STAT."Read, Mb"/LGW_STAT."Time spent,sec") "Read by LGW, MB/sec",
      LGW_STAT.Event "LGWR wait event",
      Round(LGW_STAT.avg_time_waited/1000,1) "LGWR waited,ms",
      LGW_STAT."Write requests" "LGW write requests",
      Round(LGW_STAT."Write requests"/LGW_STAT."Time spent,sec") "LGW write requests/sec",
      LGW_STAT."Read requests" "LGW read requests",
      LGW_STAT."LGWR sessions" "LGWR sessions",
      LGW_STAT."Time spent,sec" "LGWR time spent,sec",
      ROUND(DBW_STAT."Written, Mb"/DBW_STAT."Time spent,sec") "Written by DBWn, MB/sec",
      ROUND(DBW_STAT."Read, Mb"/DBW_STAT."Time spent,sec") "Read by DBWn, MB/sec",
      Round(DBW_STAT.avg_time_waited/1000,1) "DBWn waited,ms",
      Round(DBW_STAT."Write requests"/DBW_STAT."Time spent,sec") "DBWn write requests/sec",
      Round(DBW_STAT."Read requests"/DBW_STAT."Time spent,sec") "DBWn read requests/sec",
      DBW_STAT."Active sess DBWn" ,
      DBW_STAT."DBW processes on CPU",
      DBW_STAT."DBW processes on db file parallel write",
      DBW_STAT."DBW processes on db file async I/O submit",
      DBW_STAT."DBW processes on latch: redo writing"
from 
    ASH_t  
    LEFT JOIN (select * from ASH where RANK=1) ASH1 on ASH_t.sample_time=ASH1.sample_time 
    LEFT JOIN (SELECT * FROM ASH WHERE RANK=2) ASH2 ON ASH_t.SAMPLE_TIME=ASH2.SAMPLE_TIME 
    LEFT JOIN (SELECT * FROM ASH WHERE RANK=3) ASH3 ON ASH_t.SAMPLE_TIME=ASH3.SAMPLE_TIME 
    LEFT JOIN (SELECT * FROM ASH WHERE RANK=4) ASH4 ON ASH_t.SAMPLE_TIME=ASH4.SAMPLE_TIME 
    LEFT JOIN (SELECT * FROM ASH WHERE RANK=5) ASH5 ON ASH_t.SAMPLE_TIME=ASH5.SAMPLE_TIME 
    LEFT JOIN LGW_STAT ON LGW_STAT.SAMPLE_TIME=ASH_t.SAMPLE_TIME
    LEFT JOIN DBW_STAT ON DBW_STAT.SAMPLE_TIME=ASH_t.SAMPLE_TIME
ORDER BY ASH_t.SAMPLE_TIME;