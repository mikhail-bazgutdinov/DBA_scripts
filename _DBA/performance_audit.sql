alter session set nls_date_format='dd.mm.yyyy hh24:mi:ss';
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = ', ';
--
select instance_name,host_name from v$instance;
--Redo generation per week
select --TRUNC(FIRST_TIME,'ww') "week", 
ROUND(AVG(SUM(blocks*BLOCK_SIZE)/1024/1024/1024),-1) "Redo size total,Gb"
from V$ARCHIVED_LOG
where DEST_ID=1
--and to_char(FIRST_TIME,'hh24')='10'
and FIRST_TIME>sysdate-100
group by TRUNC(FIRST_TIME,'ww');

--Database size and files number
select a.*,(select value from v$parameter where name='db_files') "db_files" 
from (select Round(sum(bytes)/1024/1024/1024) "Size, GB", count(*) "Files"
from v$datafile df) a;

show parameter cpu

--Active sessions in peak time
select --begin_time
Round(avg(sum(case when metric_name='Average Active Sessions' then Round(value,2) end))) "Average Active Sessions" 
,Round(avg(sum(case when metric_name='I/O Megabytes per Second' then Round(value,2) end))) "I/O,MB per Second" 
,Round(avg(sum(case when metric_name='Physical Reads Per Sec' then Round(value,2) end)),-2) "Physical Reads Per Second" 
,Round(avg(sum(case when metric_name='Average Synchronous Single-Block Read Latency' then Round(value,2) end)),1) "Avg Read Latency,ms" 
,Round(avg(sum(case when metric_name='User Transaction Per Sec' then Round(value,2) end)),1) "User Transaction Per Sec" 
,Round(avg(sum(case when metric_name='CPU Usage Per Sec' then Round(value,2) end)),-1) "CPU Usage,CentiSeconds Per Second" 
,Round(avg(sum(case when metric_name='Network Traffic Volume Per Sec' then Round(value,2) end))/1024/1024,0) "Network Traffic,MB/sec" 
--,Round(avg(sum(case when metric_name='I/O Requests per Second' then Round(value,2) end)),-2) "I/O Requests per Second"  
--,Round(avg(sum(case when metric_name='Logons Per Sec' then Round(value,2) end)),1) "Logons Per Sec" 
from DBA_HIST_SYSMETRIC_HISTORY  -- Здесь данные из AWR
--v$sysmetric_history  -- Здесь последний час работы базы
where 
begin_time > sysdate-14  
and to_char(begin_time,'hh24') in ('09','10','11','12','13','14','15','16','17')
and to_char(begin_time,'D') in ('1','2','3','4','5')
and group_id=2
group by --dbid,
begin_time;