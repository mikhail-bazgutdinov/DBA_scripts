--Total sessions
clear screen
set feedback off
col LOG_MODE for a15
col OPEN_MODE for a15
col DATABASE_ROLE for a20
select name "Database",DATABASE_ROLE, LOG_MODE, OPEN_MODE from v$database;

col instance_name for a15
col host_name for a35
select  instance_number "Inst num"
        ,host_name
        ,instance_name
        ,(select count(*) from v$session where username is not null and program not like 'oracle%(J%') "Total sess"
        ,(select count(case when status='ACTIVE' and wait_class<>'Idle' then 1 end) from v$session) "Active sess"
        ,startup_time
        ,(select min(logon_time) from v$session where username is not null and program not like 'oracle%(J%') "Users conn since"
        ,(select FIRST_TIME from v$log l where status='CURRENT' and l.thread#=i.thread#) "Last log switch"
        ,sysdate "Sysdate"
from v$instance i;

col STATUS for a15
col DESTINATION for a70
col ARCHIVER for a10
select DEST_ID,STATUS,ARCHIVER,DESTINATION,error from v$archive_dest where status<>'INACTIVE' and log_sequence<>0;

--Sessions by username
col "User" for a30
select * from (
select * from
(
select nvl(username,'_'||type) "User",count(*) "Sessions", count(case when status='ACTIVE' and wait_class<>'Idle' then 1 end) "Active sess"
from v$session
group by nvl(username,'_'||type)
)
order by decode("User",'_BACKGROUND',1,'SYS',2,'DBSNMP',3,'SYSRAC',4,'_USER',5,6),"Sessions" desc nulls last
) where rownum<15;

set heading off
col Alert_log for a150
select 'Alert log:  ' || VALUE||'/alert_' || (select instance_name from v$instance) ||'.log'  Alert_log from v$diag_info where NAME='Diag Trace';

set heading on
set feedback on
