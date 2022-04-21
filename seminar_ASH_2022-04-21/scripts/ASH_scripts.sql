--======================================================================================
-- By Waitclasses
--======================================================================================
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
  --ASH_dbdpc_210210141842 SES
  V$ACTIVE_SESSION_HISTORY SES
WHERE 1=1
  --and SES.SESSION_STATE='WAITING'
  --and SES.SAMPLE_TIME>sysdate-1/24/60
  AN SES.SAMPLE_TIME between to_date('10.02.2021 14:15:30','dd.mm.yyyy hh24:mi:ss') and to_date('10.02.2021 14:17:30','dd.mm.yyyy hh24:mi:ss')
GROUP BY 
  TO_CHAR(SES.SAMPLE_TIME,'yyyy-mm-dd'),
  TO_CHAR(SES.SAMPLE_TIME,'hh24:mi:ss')
ORDER BY 
  --TO_CHAR(SES.SAMPLE_TIME,'yyyy-mm-dd'),
  TO_CHAR(SES.SAMPLE_TIME,'hh24:mi:ss');


--======================================================================================
-- Different Top's based on ASH
--======================================================================================
select
     ash.session_id sid,
     ash.session_serial# serial#,
     ash.user_id user_id,
     ash.program,
	 ash.module,
	 ash.action,
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
--and sample_time>sysdate-10/1440 -- 10 last minutes
--and sample_time between to_date('20.04.2022 08:00:00','dd.mm.yyyy hh24:mi:ss') and to_date('20.04.2022 08:00:00','dd.mm.yyyy hh24:mi:ss')
group by session_id,user_id,session_serial#,program
order by sum(decode(session_state,'ON CPU',1,1)) desc;



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
        max(topsession.CPU)              "CPU",
        max(topsession.WAIT)       "WAITING",
        max(topsession.IO)                  "IO",
        max(topsession.TOTAL)           "TOTAL"
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
--and sample_time>sysdate-10/1440 -- 10 last minutes
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
   order by max(topsession.TOTAL) desc
/