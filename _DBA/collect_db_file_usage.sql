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
        DELETE FROM ACS_DB_PARAM_HIST WHERE INST_ID=DBNAME_rec.ID and param_name='DB_FILES limit usage' AND TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE);
        
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

         
        -- Retrieve all non-default parameters
        execute immediate 'INSERT INTO ACS_DB_PARAM_HIST (INST_ID, PARAM_NAME, PARAM_VALUE) SELECT ' || DBNAME_rec.ID || ', ''DB_FILES limit usage'' , 
            to_char((select count(*) from v$datafile@' || v_link_name ||')) 
          from dual';
      
        -- Retrieve all non-default parameters
  --      EXECUTE IMMEDIATE 'INSERT INTO ACS_DB_PARAM_HIST (INST_ID, PARAM_NAME, PARAM_VALUE) SELECT ' || DBNAME_REC.ID || ', ''ALTER_USER_TRG trigger'' , 
--            to_char((SELECT MAX(OBJECT_TYPE || '' - '' || STATUS|| '' - '' || TO_CHAR(LAST_DDL_TIME,''dd.mm.yyyy'')) FROM DBA_OBJECTS@' || v_link_name || ' WHERE OBJECT_NAME=''ALTER_USER_TRG'')) 
          --from dual';

        COMMIT;
      
     EXCEPTION 
       when OTHERS then 
       v_error_msg := SQLERRM;
       -- log error to value field
		   dbms_output.put_line ('DB_FILES limit usage@' || v_link_name || ' - ' || v_error_msg);
       INSERT INTO ACS_DB_PARAM_HIST (INST_ID, PARAM_VALUE, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_error_msg , 'error while collecting DB_FILES limit usage',TRUNC(SYSDATE));
       commit;
     end;          
END LOOP;
CLOSE DBNAME_CUR; 
end;
/

select count(*) from dba_data_files;
--errors when collecting parameter
select lower(db.database_name) dbname, instance_name, db.host_name, nvl(par.param_value,'Not collected') "Error", dblink_name
from ACS_DB_PARAM_HIST par right join ACS_DB_INSTANCE db on par.INST_ID=db.ID
and (PAR.PARAM_NAME='error while collecting DB_FILES limit usage' or PAR.PARAM_NAME is null)
AND (TRUNC(par.DATE_COLLECTED)=TRUNC(SYSDATE) or TRUNC(par.DATE_COLLECTED) is null)
WHERE db.INSTANCE_TYPE in ('single','rac')
order by LOWER(DB.DATABASE_NAME);

-- parameter report for values of single parameter 'DB_FILES limit usage'
select DB.HOST_NAME "host name", dblink_name "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE,date_collected
from ACS_DB_INSTANCE DB  left join ACS_DB_PARAM_HIST PAR on PAR.INST_ID=DB.id
and PAR.PARAM_NAME='DB_FILES limit usage'
WHERE 
--Exclude deleted databases
--DB.DEL_DATE is null
--and LOWER(DB.DATABASE_NAME) is not null
(TRUNC(par.DATE_COLLECTED) is null or TRUNC(par.DATE_COLLECTED)=(SELECT MAX(TRUNC(DATE_COLLECTED)) from ACS_DB_PARAM_HIST where PARAM_NAME='ALTER_USER_TRG trigger'))
ORDER BY DB.HOST_NAME, LOWER(DB.DATABASE_NAME);

-- parameter report for values of 2 parameters
with par1 as (
select DB.HOST_NAME "host name", dblink_name "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE 
from ACS_DB_INSTANCE DB  join ACS_DB_PARAM_HIST PAR on PAR.INST_ID=DB.id
and PAR.PARAM_NAME='db_files'
AND TRUNC(par.DATE_COLLECTED)=(select max(trunc(date_collected)) from ACS_DB_PARAM_HIST)
WHERE 
DB.DEL_DATE is null
and LOWER(DB.DATABASE_NAME) is not null
order by TO_NUMBER(PARAM_VALUE) desc, DB.HOST_NAME, LOWER(DB.DATABASE_NAME)),
par2 as (
select DB.HOST_NAME "host name", dblink_name "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE 
from ACS_DB_INSTANCE DB  join ACS_DB_PARAM_HIST PAR on PAR.INST_ID=DB.id
and PAR.PARAM_NAME='DB_FILES limit usage'
AND TRUNC(par.DATE_COLLECTED)=(select max(trunc(date_collected)) from ACS_DB_PARAM_HIST)
WHERE 
DB.DEL_DATE is null
and LOWER(DB.DATABASE_NAME) is not null
order by TO_NUMBER(PARAM_VALUE) desc, DB.HOST_NAME, LOWER(DB.DATABASE_NAME)
)
select NVL(PAR1."host name",PAR2."host name") "host name",
NVL(PAR1."database name",PAR2."database name") "database name",
PAR1.PARAM_VALUE "db_files parameter",
PAR1.SPPARAM_VALUE "db_files parameter (spfile)",
PAR2.PARAM_VALUE "# of files in V$datafile",
--PAR3.PARAM_VALUE "# of files in dba_data_files",
Round(to_number(PAR2.PARAM_VALUE)/to_number(PAR1.PARAM_VALUE)*100,0) "Usage, %"
from PAR1 full outer join PAR2 on PAR1."target name"=PAR2."target name"
order by "Usage, %" desc nulls last;