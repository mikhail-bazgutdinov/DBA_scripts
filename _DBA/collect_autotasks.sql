
------
----- Collecting autotask configuration for list of databases in ACS_DB_INSTANCE table
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
--and dblink_name='sudak_dbdpc'
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
        DELETE FROM ACS_DB_PARAM_HIST WHERE INST_ID=DBNAME_rec.ID and param_name IN ('error while collecting autotasks configuration') AND TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE);
        DELETE FROM acs_autotask_window_clients WHERE INST_ID=DBNAME_rec.ID AND TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE);
        
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

         
        -- Retrieve tables and indexes with missing or stale stats
        execute immediate 'INSERT INTO acs_autotask_window_clients (
          INST_ID,DATE_COLLECTED, WINDOW_NAME,AUTOTASK_STATUS, OPTIMIZER_STATS,SEGMENT_ADVISOR, SQL_TUNE_ADVISOR,HEALTH_MONITOR
        ) 
        SELECT ' || DBNAME_rec.ID || ' INST_ID, TRUNC(SYSDATE) DATE_COLLECTED, WINDOW_NAME,AUTOTASK_STATUS, OPTIMIZER_STATS,SEGMENT_ADVISOR, SQL_TUNE_ADVISOR,HEALTH_MONITOR
        FROM dba_autotask_window_clients@' || v_link_name ||' 
 ';
      
          
        COMMIT;
      
     EXCEPTION 
       when OTHERS then 
       v_error_msg := SQLERRM;
       -- log error to value field
		   dbms_output.put_line ('missing statistics@' || v_link_name || ' - ' || v_error_msg);
       INSERT INTO ACS_DB_PARAM_HIST (INST_ID, PARAM_VALUE, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_error_msg , 'error while collecting autotasks configuration',TRUNC(SYSDATE));
       commit;
     end;          
END LOOP;
CLOSE DBNAME_CUR; 
end;
/

--errors when collecting objects with missing statistics
select lower(db.database_name) dbname, instance_name, db.host_name, nvl(par.param_value,'Not collected') "Error", dblink_name
from ACS_DB_PARAM_HIST par join ACS_DB_INSTANCE db on par.INST_ID=db.ID
and (PAR.PARAM_NAME='error while collecting autotasks configuration' or PAR.PARAM_NAME is null)
AND (TRUNC(par.DATE_COLLECTED)=TRUNC(SYSDATE) or TRUNC(par.DATE_COLLECTED) is null)
WHERE db.INSTANCE_TYPE in ('single','rac')
order by LOWER(DB.DATABASE_NAME);

-- Autotask configuration - summary report
select 
  s.DATE_COLLECTED,
  db.host_name, 
  db.database_name, 
  NVL((SELECT RTRIM(XMLAGG(XMLELEMENT(C,decode(WINDOW_NAME,'FRIDAY_WINDOW','Fri','MONDAY_WINDOW','Mon','SATURDAY_WINDOW','Sat','SUNDAY_WINDOW','Sun','THURSDAY_WINDOW','Thu','TUESDAY_WINDOW','Tue','WEDNESDAY_WINDOW','Wed',WINDOW_NAME)|| ',') ORDER BY decode (WINDOW_NAME,'FRIDAY_WINDOW',5,'MONDAY_WINDOW',1,'SATURDAY_WINDOW',6,'SUNDAY_WINDOW',7,'THURSDAY_WINDOW',4,'TUESDAY_WINDOW',2,'WEDNESDAY_WINDOW',3,0)).EXTRACT('//text()'),',') FROM acs_autotask_window_clients a1 WHERE a1.INST_ID=s.INST_ID AND a1.DATE_COLLECTED=s.DATE_COLLECTED and a1.OPTIMIZER_STATS='ENABLED'),'Disabled') "Gather Stats Schedule",
  NVL((SELECT RTRIM(XMLAGG(XMLELEMENT(C,decode(WINDOW_NAME,'FRIDAY_WINDOW','Fri','MONDAY_WINDOW','Mon','SATURDAY_WINDOW','Sat','SUNDAY_WINDOW','Sun','THURSDAY_WINDOW','Thu','TUESDAY_WINDOW','Tue','WEDNESDAY_WINDOW','Wed',WINDOW_NAME)|| ',') ORDER BY decode (WINDOW_NAME,'FRIDAY_WINDOW',5,'MONDAY_WINDOW',1,'SATURDAY_WINDOW',6,'SUNDAY_WINDOW',7,'THURSDAY_WINDOW',4,'TUESDAY_WINDOW',2,'WEDNESDAY_WINDOW',3,0)).EXTRACT('//text()'),',') FROM acs_autotask_window_clients a1 WHERE a1.INST_ID=s.INST_ID AND a1.DATE_COLLECTED=s.DATE_COLLECTED and a1.SEGMENT_ADVISOR='ENABLED'),'Disabled') "Segment Advisor Schedule",
  NVL((SELECT RTRIM(XMLAGG(XMLELEMENT(C,decode(WINDOW_NAME,'FRIDAY_WINDOW','Fri','MONDAY_WINDOW','Mon','SATURDAY_WINDOW','Sat','SUNDAY_WINDOW','Sun','THURSDAY_WINDOW','Thu','TUESDAY_WINDOW','Tue','WEDNESDAY_WINDOW','Wed',WINDOW_NAME)|| ',') ORDER BY decode (WINDOW_NAME,'FRIDAY_WINDOW',5,'MONDAY_WINDOW',1,'SATURDAY_WINDOW',6,'SUNDAY_WINDOW',7,'THURSDAY_WINDOW',4,'TUESDAY_WINDOW',2,'WEDNESDAY_WINDOW',3,0)).EXTRACT('//text()'),',') FROM acs_autotask_window_clients a1 WHERE a1.INST_ID=s.INST_ID AND a1.DATE_COLLECTED=s.DATE_COLLECTED and a1.sql_tune_advisor='ENABLED'),'Disabled') "SQL Tuning Schedule",
  NVL((SELECT RTRIM(XMLAGG(XMLELEMENT(C,decode(WINDOW_NAME,'FRIDAY_WINDOW','Fri','MONDAY_WINDOW','Mon','SATURDAY_WINDOW','Sat','SUNDAY_WINDOW','Sun','THURSDAY_WINDOW','Thu','TUESDAY_WINDOW','Tue','WEDNESDAY_WINDOW','Wed',WINDOW_NAME)|| ',') ORDER BY decode (WINDOW_NAME,'FRIDAY_WINDOW',5,'MONDAY_WINDOW',1,'SATURDAY_WINDOW',6,'SUNDAY_WINDOW',7,'THURSDAY_WINDOW',4,'TUESDAY_WINDOW',2,'WEDNESDAY_WINDOW',3,0)).EXTRACT('//text()'),',') FROM acs_autotask_window_clients a1 WHERE a1.INST_ID=s.INST_ID AND a1.DATE_COLLECTED=s.DATE_COLLECTED and a1.health_monitor='ENABLED'),'Disabled') "Health Monitor Schedule"
from ACS_DB_INSTANCE db left join acs_autotask_window_clients s on s.INST_ID=db.ID
where 
  TRUNC(s.DATE_COLLECTED)=(select max(trunc(date_collected)) from acs_autotask_window_clients)
  --db.host_name='toro.cgs.sbrf.ru'
  and db.del_date is null
group by 
  s.DATE_COLLECTED,
  db.host_name,
  db.database_name,
  s.INST_ID
order by 
  db.host_name, 
  s.date_collected desc;
  
  -- parameter report for values of single parameter '_enable_automatic_maintenance'
select DB.HOST_NAME "host name", dblink_name "target name", DB.DATABASE_NAME "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE,PAR.PARAM_ISMODIFIED,PAR.PARAM_ISDEFAULT, PAR.SPPARAM_ISSPECIFIED,date_collected
from ACS_DB_INSTANCE DB  left join ACS_DB_PARAM_HIST PAR on PAR.INST_ID=DB.id
and PAR.PARAM_NAME like '_enable_automatic_maintenance'
WHERE 
--Exclude deleted databases
DB.DEL_DATE is null
--and LOWER(DB.DATABASE_NAME) is not null
--and LOWER(DB.DATABASE_NAME)='prod'
and (TRUNC(par.DATE_COLLECTED) is null or TRUNC(par.DATE_COLLECTED)=(SELECT MAX(TRUNC(DATE_COLLECTED)) from ACS_DB_PARAM_HIST where PARAM_NAME='_enable_automatic_maintenance'))
order by DB.HOST_NAME, LOWER(DB.DATABASE_NAME), dblink_name, PAR.PARAM_NAME;

