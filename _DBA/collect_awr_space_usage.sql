
------
----- Collecting database parameters for list of databases in ACS_DB_INSTANCE table
----- 
set serveroutput on
DECLARE

--List of databases
CURSOR DBNAME_CUR 
  is 
Select distinct ID, instance_name, database_name,dblink_name
from ACS_DB_INSTANCE db
WHERE 
--excluded all except databases
INSTANCE_TYPE in ('single','rac') 
--exclude deleted databases
AND DEL_DATE is null
AND (INSTANCE_TYPE='single' or instance_name like '%1')
--exclude already collected today
--AND NOT EXISTS (SELECT 1 from ACS_DB_PARAM_HIST dbp where dbp.INST_ID=db.id and dbp.PARAM_NAME='type of parameter file' AND dbp.DATE_COLLECTED=TRUNC(SYSDATE) and dbp.value_char is not null and dbp.value_char not like '%ORA%');
order by instance_name;

DBNAME_rec  DBNAME_CUR%ROWTYPE;                   

TYPE cursor_ref IS REF CURSOR;
c1 cursor_ref;
v_error_msg varchar2(4000);
v_sqlcode number;
v_link_name Varchar2(500);

BEGIN
OPEN DBNAME_CUR; 
LOOP 
  FETCH DBNAME_CUR INTO DBNAME_rec; 
  EXIT WHEN DBNAME_CUR%NOTFOUND; 
     begin
        --Delete data collected today.
        DELETE FROM ACS_DB_PARAM_HIST WHERE INST_ID=DBNAME_rec.ID and param_name IN ('WRM$_SNAPSHOT_DETAILS oldest entry', 'WRM$_SNAPSHOT_DETAILS size, Mb','AWR space usage', 'AWR space usage, Mb', 'AWR space usage, Gb','AWR Snapshot interval, min','AWR Retention Interval,days','AWR snapshot count') AND TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE);
        
        v_link_name := DBNAME_rec.dblink_name;
        -- test the database link
        BEGIN
            OPEN c1 FOR 'select * from dual@' || v_link_name;
            close c1;
         EXCEPTION 
           when OTHERS then 
           v_sqlcode := SQLCODE;
           v_error_msg := SQLERRM;
		   dbms_output.put_line ('Error on connecting ' || v_link_name || '. ORA-' || v_sqlcode || ' - ' || v_error_msg);
        END;
        -- Retrieve AWR space usage
        execute immediate 'INSERT INTO ACS_DB_PARAM_HIST (INST_ID, PARAM_NAME, PARAM_VALUE) SELECT ' || DBNAME_rec.ID || ', ''AWR space usage, Mb'' , 
            to_char((select Round(space_usage_kbytes/1024) "Gb" from V$SYSAUX_OCCUPANTS@' || v_link_name ||'  where OCCUPANT_NAME=''SM/AWR'')) 
          from dual';
      
        -- Retrieve AWR Snapshot interval, min
        execute immediate 'INSERT INTO ACS_DB_PARAM_HIST (INST_ID, PARAM_NAME, PARAM_VALUE) SELECT ' || DBNAME_rec.ID || ', ''AWR Snapshot interval, min'' , 
            to_char((select 
                      extract(day from snap_interval)*24*60+
                      extract(hour from snap_interval)*60 +
                    extract(minute from snap_interval) FROM dba_hist_wr_control@' || v_link_name ||' where dbid=(select dbid from v$database@' || v_link_name ||'))) 
          from dual';
      
        -- Retrieve AWR Retention Interval,days
        execute immediate 'INSERT INTO ACS_DB_PARAM_HIST (INST_ID, PARAM_NAME, PARAM_VALUE) SELECT ' || DBNAME_rec.ID || ', ''AWR Retention Interval,days'' , 
            to_char((select 
                      extract(day from retention)*24*60+
                      extract(hour from retention)*60 +
                      extract(minute from retention) FROM dba_hist_wr_control@' || v_link_name ||' where dbid=(select dbid from v$database@' || v_link_name ||'))) 
       from dual';

      --   Retrieve AWR snapshot count
        execute immediate 'INSERT INTO ACS_DB_PARAM_HIST (INST_ID, PARAM_NAME, PARAM_VALUE) SELECT ' || DBNAME_rec.ID || ', ''AWR snapshot count'' , 
            to_char((select count(distinct snap_id||INSTANCE_NUMBER) "Snapshot count" From dba_hist_snapshot@' || v_link_name ||' where dbid=(select dbid from v$database@' || v_link_name ||') and INSTANCE_NUMBER=(select INSTANCE_NUMBER from v$instance@' || v_link_name ||'))) 
        from dual';
        
        -- Retrieve WRM$_SNAPSHOT_DETAILS size
        execute immediate 'INSERT INTO ACS_DB_PARAM_HIST (INST_ID, PARAM_NAME, PARAM_VALUE) SELECT ' || DBNAME_rec.ID || ', ''WRM$_SNAPSHOT_DETAILS size, Mb'' , 
            to_char((select Round(sum(bytes)/1024/1024) "Mb" from dba_segments@' || v_link_name ||'  where SEGMENT_NAME=''WRM$_SNAPSHOT_DETAILS'')) 
          from dual';  
          
         -- Retrieve WRM$_SNAPSHOT_DETAILS oldest entry
        execute immediate 'INSERT INTO ACS_DB_PARAM_HIST (INST_ID, PARAM_NAME, PARAM_VALUE) SELECT ' || DBNAME_rec.ID || ', ''WRM$_SNAPSHOT_DETAILS oldest entry'' , 
            to_char((select to_char(min(end_time),''yyyy-mm-dd'') from sys.WRM$_SNAPSHOT_DETAILS@' || v_link_name ||')) 
          from dual';          

        COMMIT;

     EXCEPTION 
       when OTHERS then 
       v_error_msg := SQLERRM;
       -- log error to value field
		   dbms_output.put_line ('AWR space usage, Mb@' || v_link_name || ' - ' || v_error_msg);
       INSERT INTO ACS_DB_PARAM_HIST (INST_ID, PARAM_VALUE, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_error_msg , 'error while collecting AWR space usage, Mb',TRUNC(SYSDATE));
       commit;
     end;          
END LOOP;
CLOSE DBNAME_CUR; 
end;
/

select count(*) from dba_data_files;
--errors when collecting parameter
select lower(db.database_name) dbname, instance_name, db.host_name, nvl(par.param_value,'Not collected') "Error", dblink_name
from ACS_DB_PARAM_HIST par join ACS_DB_INSTANCE db on par.INST_ID=db.ID
and (PAR.PARAM_NAME='error while collecting AWR space usage, Mb' or PAR.PARAM_NAME is null)
AND (TRUNC(par.DATE_COLLECTED)=TRUNC(SYSDATE) or TRUNC(par.DATE_COLLECTED) is null)
and instance_name='abizol'
WHERE db.INSTANCE_TYPE in ('single','rac')
order by LOWER(DB.DATABASE_NAME);

-- parameter report for values of single parameter 'AWR space usage, Mb'
select DB.HOST_NAME "host name", dblink_name "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,date_collected
from ACS_DB_INSTANCE DB  left join ACS_DB_PARAM_HIST PAR on PAR.INST_ID=DB.id
and PAR.PARAM_NAME='AWR space usage, Mb'
WHERE 
--Exclude deleted databases
DB.DEL_DATE is null
--and LOWER(DB.DATABASE_NAME) is not null
and (TRUNC(par.DATE_COLLECTED) is null or TRUNC(par.DATE_COLLECTED)=(SELECT MAX(TRUNC(DATE_COLLECTED)) from ACS_DB_PARAM_HIST))
ORDER BY DB.HOST_NAME, LOWER(DB.DATABASE_NAME);

-- parameter report for values of 4 parameters
with par1 as (
select DB.HOST_NAME "host name", dblink_name "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE 
from ACS_DB_INSTANCE DB  join ACS_DB_PARAM_HIST PAR on PAR.INST_ID=DB.id
and PAR.PARAM_NAME='AWR space usage, Mb'
AND TRUNC(par.DATE_COLLECTED)=(select max(trunc(date_collected)) from ACS_DB_PARAM_HIST)
WHERE 
DB.DEL_DATE is null
and LOWER(DB.DATABASE_NAME) is not null
order by TO_NUMBER(PARAM_VALUE) desc, DB.HOST_NAME, LOWER(DB.DATABASE_NAME)),
par2 as (
select DB.HOST_NAME "host name", dblink_name "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE 
from ACS_DB_INSTANCE DB  join ACS_DB_PARAM_HIST PAR on PAR.INST_ID=DB.id
WHERE 
PAR.PARAM_NAME='AWR snapshot count'
AND 
TRUNC(par.DATE_COLLECTED)=(select max(trunc(date_collected)) from ACS_DB_PARAM_HIST)
AND DB.DEL_DATE is null
and LOWER(DB.DATABASE_NAME) is not null
order by TO_NUMBER(PARAM_VALUE) desc, DB.HOST_NAME, LOWER(DB.DATABASE_NAME)
),
par3 as (
select DB.HOST_NAME "host name", dblink_name "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE 
from ACS_DB_INSTANCE DB  join ACS_DB_PARAM_HIST PAR on PAR.INST_ID=DB.id
and PAR.PARAM_NAME='AWR Snapshot interval, min'
AND TRUNC(par.DATE_COLLECTED)=(select max(trunc(date_collected)) from ACS_DB_PARAM_HIST)
WHERE 
DB.DEL_DATE is null
and LOWER(DB.DATABASE_NAME) is not null
order by TO_NUMBER(PARAM_VALUE) desc, DB.HOST_NAME, LOWER(DB.DATABASE_NAME)
),
par4 as (
select DB.HOST_NAME "host name", dblink_name "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE 
from ACS_DB_INSTANCE DB  join ACS_DB_PARAM_HIST PAR on PAR.INST_ID=DB.id
and PAR.PARAM_NAME='AWR Retention Interval,days'
AND TRUNC(par.DATE_COLLECTED)=(select max(trunc(date_collected)) from ACS_DB_PARAM_HIST)
WHERE 
DB.DEL_DATE is null
and LOWER(DB.DATABASE_NAME) is not null
order by TO_NUMBER(PARAM_VALUE) desc, DB.HOST_NAME, LOWER(DB.DATABASE_NAME)
),
par5 as (
select DB.HOST_NAME "host name", dblink_name "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE 
from ACS_DB_INSTANCE DB  join ACS_DB_PARAM_HIST PAR on PAR.INST_ID=DB.id
and PAR.PARAM_NAME='WRM$_SNAPSHOT_DETAILS size, Mb'
AND TRUNC(par.DATE_COLLECTED)=(select max(trunc(date_collected)) from ACS_DB_PARAM_HIST)
WHERE 
DB.DEL_DATE is null
and LOWER(DB.DATABASE_NAME) is not null
)
,
par6 as (
select DB.HOST_NAME "host name", dblink_name "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE 
from ACS_DB_INSTANCE DB  join ACS_DB_PARAM_HIST PAR on PAR.INST_ID=DB.id
and PAR.PARAM_NAME='WRM$_SNAPSHOT_DETAILS oldest entry'
AND TRUNC(par.DATE_COLLECTED)=(select max(trunc(date_collected)) from ACS_DB_PARAM_HIST)
WHERE 
DB.DEL_DATE is null
and LOWER(DB.DATABASE_NAME) is not null
)
select NVL(PAR1."host name",PAR2."host name") "host name",
NVL(PAR1."database name",PAR2."database name") "database name",
PAR1.PARAM_VALUE "AWR space usage, Mb",
PAR2.PARAM_VALUE "AWR snapshot count",
PAR3.PARAM_VALUE "AWR Snapshot interval, min",
PAR4.PARAM_VALUE/24/60 "AWR Retention Interval,days",
PAR5.PARAM_VALUE "WRM$_SNAPSHOT_DETAILS size, Mb",
PAR6.PARAM_VALUE "WRM$_SNAPSHOT_DETAILS oldest"
from PAR1 full outer join PAR2 on PAR1."target name"=PAR2."target name"
full outer join PAR3 on PAR1."target name"=PAR3."target name"
full outer join PAR4 on PAR1."target name"=PAR4."target name"
full outer join PAR5 on PAR1."target name"=PAR5."target name"
full outer join PAR6 on PAR1."target name"=PAR6."target name"
order by "host name", "database name";

