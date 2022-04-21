-- Testcase from Mauro Pagano
-- installed on anna_morpheus

create tablespace ASH datafile '/oradata/morpheus/ash_01.dbf' size 10M autoextend on next 10M maxsize 10G;
create user ASH identified by ash2017 default tablespace ASH;
grant create session, create table, select any dictionary to ASH;
alter user ASH quota unlimited on ASH;


connect ASH/ash2017
set lines 200
set timing on
-- 8x dba_objects 
create table ASH.t_case1 as 
select * 
	from 
		dba_objects, 
		(select rownum n1 from dual connect by rownum <= 8); 

-- Index on OBJECT_TYPE
create index ASH.t_case1_objtype on t_case1(object_type); 

-- 32x dba_objects 
create table ASH.t_case3 as 
select * from t_case1, 
(select rownum from dual connect by rownum <= 4);

select count(*) from t_case1;
select count(*) from t_case3;

-- AWR SQL ID: dskp9f0r23dj3 
-- run in 3 concurrent sessions, start with some time shift (not simultaneously)
conn ash/ash2017
SET AUTOTRACE ON EXPLAIN
SET AUTOTRACE ON
set timing on 
set time on
set lines 200
var B1 varchar2(40)
exec :B1 := 'I%';  --change to 'S%', 'T%', 'I%' in different sessions
select /*+ LEADING(A) USE_NL(B) */ 
	count(*) 
from t_case1 a join t_case1 b on a.object_type = b.object_type
where b.object_type like :B1
and rownum<5e9;

-- AWR SQL ID:  
-- run in 3 concurrent sessions, start with some time shift (not simultaneously)
conn ash/ash2017
SET AUTOTRACE ON EXPLAIN
SET AUTOTRACE ON
set timing on 
set time on
set lines 200
var B1 varchar2(40)
--change to 'S%', 'T%', 'I%' in different sessions. Add PARALLEL(4) hint for I%.
exec :B1 := 'I%';  
select /*+ LEADING(A) USE_NL(B) PARALLEL(4)*/ 
	count(*) ,:B1
from t_case1 a join t_case3 b on a.owner = b.owner
where a.object_type like :B1
and rownum<1e8;


-- Save ASH to table to keep it from being purged.
create table ASH_dskp9f0r23dj3 as select * from v$active_session_history where sql_id='dskp9f0r23dj3';


-- How long did my SQL execution take? - v$sqlstats
select 
	executions, 
	end_of_fetch_count end_of_fetch,
	round(elapsed_time/1e6) elapsed_sec, 
	round(buffer_gets/1e6,1) buff_gets_mln 
from 
	v$sqlstats
where 
	sql_id = 'dskp9f0r23dj3'; 
	
-- How long did my SQL execution take? - AWR (dba_hist_sqlstat)
select 
	snap_id, 
	executions_delta e_d, 
	executions_total e_t, 
	end_of_fetch_count_delta eof_d, 
	trunc(elapsed_time_delta/1e6) et_d_s, 
	trunc(elapsed_time_total/1e6) et_t_s, 
	buffer_gets_delta bg_d, 
	buffer_gets_total bg_t 
from 
	dba_hist_sqlstat 
where 
	sql_id = 'dskp9f0r23dj3' 
order by 
	snap_id; 

-- SQL execution begin and end for every execution
select 
	a.sql_exec_id,
    a.sql_exec_start,
    a.module,
    a.session_id,
    cast(min(a.sample_time) as date) "Started",
    cast(max(a.sample_time) as date) "Ended",
    Round((cast(max(a.sample_time) as date) - cast(min(a.sample_time) as date))*24*60*60) "Elapsed time, sec"
from 
	v$active_session_history a
where 
	sql_id = 'dskp9f0r23dj3' 
group by    a.sql_exec_id,    a.sql_exec_start,    a.module,    a.session_id
order by min(a.sample_time);

-- CPU and waits for every SQL execution
select 
    a.sql_exec_start,
    NVL(a.event,'ON CPU') "Wait event", 
    COUNT(*) "ASH samples cnt",
	Round(SUM(TM_DELTA_TIME)/1e6) TM_DELTA_TIME,
	Round(SUM(DELTA_TIME)/1e6) DELTA_TIME,
    Round((cast(max(a.sample_time) as date) - 
		   cast(min(a.sample_time) as date))*24*60*60) "Elapsed time, sec"
from 
	v$active_session_history a
where 
	sql_id = 'dskp9f0r23dj3' 
group by    a.sql_exec_start, NVL(a.event,'ON CPU')
order by min(a.sample_time);

-- Was PX (parallel execution) involved or not?
select 
    a.sql_exec_id, NVL(a.QC_SESSION_ID, a.session_id) session_id, 
	ROUND(PX_FLAGS/2097152) "Degree",
    a.sql_exec_start,
    NVL(a.event,'ON CPU') "Wait event", 
    COUNT(*) "ASH samples cnt",
	Round(SUM(TM_DELTA_CPU_TIME)/1e6) CPU_TIME,
	Round(SUM(TM_DELTA_DB_TIME)/1e6) DB_TIME,    
    Round((cast(max(a.sample_time) as date) - 
           cast(min(a.sample_time) as date))*24*60*60) "Elapsed time, sec"
from 
	v$active_session_history a
where 
	sql_id in ('7wwa8agka0xg8','3xcgx55t55juc') 
group by   NVL(a.QC_SESSION_ID, a.session_id), a.PX_FLAGS, a.sql_exec_id, 
			a.sql_exec_start, NVL(a.event,'ON CPU')
order by min(a.sample_time);


select 
	OWNER, name, LOCKED_TOTAL "Locked", PINNED_TOTAL "Pinned", FULL_HASH_VALUE 
from v$db_object_cache 
where HASH_VALUE={P1 value};

alter system set "_kgl_debug"="hash='c4982a06e69512c0348c4331433f51de' debug=33554432";

alter system set _kgl_hot_object_copies=128;


