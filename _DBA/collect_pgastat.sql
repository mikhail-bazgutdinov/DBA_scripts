------
----- Collecting PGA stats usage from v$pgastat for list of databases in ACS_DB_INSTANCE table
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
--AND NOT EXISTS (SELECT 1 from ACS_PGASTAT_HIST dbp where dbp.INST_ID=db.id and dbp.PARAM_NAME='type of parameter file' AND dbp.DATE_COLLECTED=TRUNC(SYSDATE) and dbp.value_char is not null and dbp.value_char not like '%ORA%');
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
        DELETE FROM ACS_PGASTAT_HIST WHERE INST_ID=DBNAME_rec.ID  AND TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE);
        DELETE FROM ACS_DB_PARAM_HIST WHERE INST_ID=DBNAME_REC.ID AND PARAM_NAME IN ('error while collecting PGASTATS') AND TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE);
               
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

         
        -- Retrieve sum size of undo segments from dba_segments
        EXECUTE IMMEDIATE 'INSERT INTO ACS_PGASTAT_HIST (INST_ID, PGASTAT_NAME, PGASTAT_VALUE,PGASTAT_UNIT) ' || 
                          ' SELECT ' || DBNAME_rec.ID || ', p.* from v$pgastat@' || v_link_name || ' p';
        COMMIT;
     
     EXCEPTION 
       when OTHERS then 
       v_error_msg := SQLERRM;
       -- log error to value field
		   DBMS_OUTPUT.PUT_LINE ('DBA_SEGMENTS sum bytes@' || V_LINK_NAME || ' - ' || V_ERROR_MSG);
       INSERT INTO ACS_DB_PARAM_HIST (INST_ID, PARAM_VALUE, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_error_msg , 'error while collecting PGASTATS',TRUNC(SYSDATE));
       commit;
     end;          
END LOOP;
CLOSE DBNAME_CUR; 
end;
/


--errors when collecting parameter
select lower(db.database_name) dbname, instance_name, db.host_name, nvl(par.param_value,'Not collected') "Error", dblink_name
from ACS_DB_PARAM_HIST par right join ACS_DB_INSTANCE db on par.INST_ID=db.ID
and (PAR.PARAM_NAME='error while collecting PGASTATS')
AND par.DATE_COLLECTED=TRUNC(SYSDATE) 
WHERE DB.INSTANCE_TYPE IN ('single','rac')
AND 0=(SELECT COUNT(*) FROM ACS_PGASTAT_HIST PGA WHERE PGA.INST_ID=DB.ID AND PGA.DATE_COLLECTED=TRUNC(SYSDATE))
and db.del_date is null
order by LOWER(DB.DATABASE_NAME);


-- parameter report for estimation of "Sberbank PGA usage metric"
with par1 as (
  SELECT DB.HOST_NAME "host name", 
         DBLINK_NAME "target name", 
         LOWER(DB.DATABASE_NAME) "database name",
         DB.INSTANCE_NAME, 
         PGA.PGASTAT_NAME,
         PGA.PGASTAT_VALUE,
         PGA.PGASTAT_UNIT 
  FROM ACS_DB_INSTANCE DB  JOIN ACS_PGASTAT_HIST PGA ON PGA.INST_ID=DB.ID
  AND PGA.PGASTAT_NAME='aggregate PGA target parameter'
  AND pga.DATE_COLLECTED=(select max(date_collected) from ACS_PGASTAT_HIST)
  WHERE 
  DB.DEL_DATE is null
  AND LOWER(DB.DATABASE_NAME) IS NOT NULL
  ORDER BY TO_NUMBER(PGA.PGASTAT_VALUE) DESC, DB.HOST_NAME, LOWER(DB.DATABASE_NAME)
),
par2 as (
  SELECT DB.HOST_NAME "host name", 
         DBLINK_NAME "target name", 
         LOWER(DB.DATABASE_NAME) "database name",
         DB.INSTANCE_NAME, 
         PGA.PGASTAT_NAME,
         PGA.PGASTAT_VALUE,
         PGA.PGASTAT_UNIT 
  FROM ACS_DB_INSTANCE DB  JOIN ACS_PGASTAT_HIST PGA ON PGA.INST_ID=DB.ID
  AND PGA.PGASTAT_NAME='total PGA allocated'
  AND pga.DATE_COLLECTED=(select max(date_collected) from ACS_PGASTAT_HIST)
  WHERE 
  DB.DEL_DATE is null
  AND LOWER(DB.DATABASE_NAME) IS NOT NULL
  ORDER BY TO_NUMBER(PGA.PGASTAT_VALUE) DESC, DB.HOST_NAME, LOWER(DB.DATABASE_NAME)
),
par3 as (
  SELECT DB.HOST_NAME "host name", 
         DBLINK_NAME "target name", 
         LOWER(DB.DATABASE_NAME) "database name",
         DB.INSTANCE_NAME, 
         PGA.PGASTAT_NAME,
         PGA.PGASTAT_VALUE,
         PGA.PGASTAT_UNIT 
  FROM ACS_DB_INSTANCE DB  JOIN ACS_PGASTAT_HIST PGA ON PGA.INST_ID=DB.ID
  AND PGA.PGASTAT_NAME='maximum PGA allocated'
  AND pga.DATE_COLLECTED=(select max(date_collected) from ACS_PGASTAT_HIST)
  WHERE 
  DB.DEL_DATE is null
  AND LOWER(DB.DATABASE_NAME) IS NOT NULL
  ORDER BY TO_NUMBER(PGA.PGASTAT_VALUE) DESC, DB.HOST_NAME, LOWER(DB.DATABASE_NAME)
),
par4 as (
  SELECT DB.HOST_NAME "host name", 
         DBLINK_NAME "target name", 
         LOWER(DB.DATABASE_NAME) "database name",
         DB.INSTANCE_NAME, 
         PGA.PGASTAT_NAME,
         PGA.PGASTAT_VALUE,
         PGA.PGASTAT_UNIT 
  FROM ACS_DB_INSTANCE DB  JOIN ACS_PGASTAT_HIST PGA ON PGA.INST_ID=DB.ID
  AND PGA.PGASTAT_NAME='cache hit percentage'
  AND pga.DATE_COLLECTED=(select max(date_collected) from ACS_PGASTAT_HIST)
  WHERE 
  DB.DEL_DATE is null
  AND LOWER(DB.DATABASE_NAME) IS NOT NULL
)
,
par5 as (
  SELECT DB.HOST_NAME "host name", 
         DBLINK_NAME "target name", 
         LOWER(DB.DATABASE_NAME) "database name",
         DB.INSTANCE_NAME, 
         PGA.PGASTAT_NAME,
         PGA.PGASTAT_VALUE,
         PGA.PGASTAT_UNIT 
  FROM ACS_DB_INSTANCE DB  JOIN ACS_PGASTAT_HIST PGA ON PGA.INST_ID=DB.ID
  AND PGA.PGASTAT_NAME='process count'
  AND pga.DATE_COLLECTED=(select max(date_collected) from ACS_PGASTAT_HIST)
  WHERE 
  DB.DEL_DATE is null
  AND LOWER(DB.DATABASE_NAME) IS NOT NULL
),
par6 as (
  SELECT DB.HOST_NAME "host name", 
         DBLINK_NAME "target name", 
         LOWER(DB.DATABASE_NAME) "database name",
         DB.INSTANCE_NAME, 
         PGA.PGASTAT_NAME,
         PGA.PGASTAT_VALUE,
         PGA.PGASTAT_UNIT 
  FROM ACS_DB_INSTANCE DB  JOIN ACS_PGASTAT_HIST PGA ON PGA.INST_ID=DB.ID
  AND PGA.PGASTAT_NAME='max processes count'
  AND pga.DATE_COLLECTED=(select max(date_collected) from ACS_PGASTAT_HIST)
  WHERE 
  DB.DEL_DATE is null
  AND LOWER(DB.DATABASE_NAME) IS NOT NULL
)
select NVL(PAR1."host name",PAR2."host name") "host name",
NVL(PAR1."database name",PAR2."database name") "database name",
PAR1.INSTANCE_NAME,
ROUND(PAR1.PGASTAT_VALUE/1024/1024/1024,1) "aggregate_PGA_target,Gb",
ROUND(PAR2.PGASTAT_VALUE/1024/1024/1024,1) "PGA allocated,Gb",
ROUND(PAR3.PGASTAT_VALUE/1024/1024/1024,1) "maximum PGA allocated,Gb",
Round(PAR2.PGASTAT_VALUE/PAR1.PGASTAT_VALUE,1) "Sberbank PGA usage metric",
ROUND(PAR4.PGASTAT_VALUE,0) "cache hit percentage",
ROUND(PAR5.PGASTAT_VALUE,0) "process count",
Round(PAR6.PGASTAT_VALUE,0) "max processes count"
from PAR1  join PAR2 on PAR1."target name"=PAR2."target name"
 join PAR3 on PAR1."target name"=PAR3."target name"
 left join PAR4 on PAR1."target name"=PAR4."target name"
 left join PAR5 on PAR1."target name"=PAR5."target name"
 LEFT JOIN PAR6 ON PAR1."target name"=PAR6."target name"
ORDER BY "Sberbank PGA usage metric" DESC, 1,2,3;