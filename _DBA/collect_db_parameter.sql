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
--AND NOT EXISTS (SELECT 1 from ACS_DB_PARAM_HIST dbp where dbp.INST_ID=db.id and dbp.PARAM_NAME='spfile' AND dbp.DATE_COLLECTED=TRUNC(SYSDATE) and dbp.PARAM_VALUE is not null and dbp.PARAM_VALUE not like '%ORA%')
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
        DELETE FROM ACS_DB_PARAM_HIST WHERE INST_ID=DBNAME_rec.ID AND (PARAM_ISDEFAULT is not null OR SPPARAM_ISSPECIFIED is not null OR param_name='error while collecting from v$system_parameter2') AND TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE);
        
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
        EXECUTE IMMEDIATE 'INSERT INTO ACS_DB_PARAM_HIST (INST_ID, DATE_COLLECTED, PARAM_NAME, PARAM_VALUE, spparam_value,PARAM_UPDATE_COMMENT,SPPARAM_ISSPECIFIED,PARAM_ISDEFAULT,PARAM_ISMODIFIED,SPPARAM_SID) ' ||
                          ' SELECT ' || DBNAME_REC.ID || ',trunc(sysdate),nvl(p.name,sp.name) ,p.display_value, sp.display_value,p.update_comment,sp.isspecified,p.isdefault,p.ismodified,sp.sid ' || 
                          ' from  v$system_parameter2@' || V_LINK_NAME || ' p full outer join V$SPPARAMETER@' || V_LINK_NAME || ' sp on P.name=SP.name ' || 
                          ' and P.VALUE=CASE WHEN P.NAME IN (''spfile'',''event'',''control_files'',''_kgl_debug'',''db_file_name_convert'',''log_file_name_convert'',''listener_networks'',''local_listener'',''service_names'',''utl_file_dir'',''log_archive_dest_2'',''log_archive_dest_4'') ' ||
                          '  THEN SP.VALUE ' || 
                          '  ELSE P.VALUE ' ||
                          '  end ' || 
                          ' WHERE (P.DISPLAY_VALUE is not null or SP.DISPLAY_VALUE is not null or p.name=''spfile'' or p.ismodified<>''FALSE'') ' || 
                          ' AND (SP.SID is null OR SP.SID=''*'' OR SP.SID=(select i.instance_name from v$instance@' || V_LINK_NAME || ' i))';
        COMMIT;
      
     EXCEPTION 
       when OTHERS then 
       v_error_msg := SQLERRM;
       -- log error to value field
		   dbms_output.put_line ('Error on retrieving v$parameter@' || v_link_name || ' - ' || v_error_msg);
       INSERT INTO ACS_DB_PARAM_HIST (INST_ID, PARAM_VALUE, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_error_msg , 'error while collecting from v$system_parameter2',TRUNC(SYSDATE));
       commit;
     end;          
END LOOP;
CLOSE DBNAME_CUR; 
end;
/
DELETE FROM ACS_DB_PARAM_HIST WHERE (PARAM_ISDEFAULT IS NOT NULL OR PARAM_NAME='error while collecting from v$system_parameter2') AND TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE)-1;
--select * from V$SYSTEM_PARAMETER2@vetluga_ekp;
SELECT NVL(P.NAME,SP.NAME) ,P.DISPLAY_VALUE, SP.DISPLAY_VALUE,P.UPDATE_COMMENT,SP.ISSPECIFIED,P.ISDEFAULT,P.ISMODIFIED ,SP.SID,P.ORDINAL,SP.ORDINAL
FROM              V$SYSTEM_PARAMETER2@inari_standin1 P 
  FULL OUTER JOIN V$SPPARAMETER@inari_standin1 SP ON 
    P.NAME=SP.NAME
  AND P.VALUE=CASE WHEN P.NAME IN ('spfile','event','control_files','_kgl_debug','db_file_name_convert','log_file_name_convert','listener_networks','local_listener','service_names','utl_file_dir','log_archive_dest_2','log_archive_dest_4')
      THEN SP.VALUE
      ELSE P.VALUE
      end      
WHERE (P.DISPLAY_VALUE IS NOT NULL OR SP.DISPLAY_VALUE IS NOT NULL OR P.NAME='spfile' OR P.ISMODIFIED<>'FALSE' OR SP.ISSPECIFIED='TRUE')
AND (SP.SID=(SELECT I.INSTANCE_NAME FROM V$INSTANCE@INARI_STANDIN1 I)
      OR 
     SP.SID='*' 
     OR SP.SID is null
    )
order by 1;

--errors when collecting parameter
select lower(db.database_name) dbname, instance_name, db.host_name, nvl(par.param_value,'Not collected') "Error", dblink_name
from ACS_DB_PARAM_HIST par join ACS_DB_INSTANCE db on par.INST_ID=db.ID
and (PAR.PARAM_NAME='error while collecting from v$system_parameter2')
WHERE db.INSTANCE_TYPE in ('single','rac')
and db.del_date is null
AND (TRUNC(par.DATE_COLLECTED)=TRUNC(SYSDATE) or TRUNC(par.DATE_COLLECTED) is null)
order by LOWER(DB.DATABASE_NAME);

--Number of parameters collected
SELECT LOWER(DB.DATABASE_NAME) DBNAME, INSTANCE_NAME, DB.HOST_NAME, COUNT(*) "Number of params"
from ACS_DB_PARAM_HIST par right join ACS_DB_INSTANCE db on par.INST_ID=db.ID AND (TRUNC(par.DATE_COLLECTED)=TRUNC(SYSDATE) or par.DATE_COLLECTED is null)
WHERE 
db.INSTANCE_TYPE in ('single','rac')
AND DB.DEL_DATE IS NULL
group by lower(db.database_name), instance_name, db.host_name
order by "Number of params";

SELECT LOWER(DB.DATABASE_NAME) DBNAME, INSTANCE_NAME, DB.HOST_NAME, par.*
from ACS_DB_PARAM_HIST par right join ACS_DB_INSTANCE db on par.INST_ID=db.ID 
WHERE 
db.INSTANCE_TYPE in ('single','rac')
AND DB.DEL_DATE IS NULL
AND DB.DATABASE_NAME='resteg' and par.param_isdefault is not null
order by TRUNC(par.DATE_COLLECTED) desc, par.param_name;
--AND TRUNC(par.DATE_COLLECTED)=TRUNC((select max(par1.DATE_COLLECTED) from ACS_DB_PARAM_HIST par1 where par1.inst_id=par.inst_id and par.param_name='db_name'));


-- Databases were started not using spfile (with text init-file)
SELECT DB.HOST_NAME "host name", DBLINK_NAME "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE,DATE_COLLECTED
FROM ACS_DB_INSTANCE DB  JOIN ACS_DB_PARAM_HIST PAR ON PAR.INST_ID=DB.ID and PAR.PARAM_NAME='spfile'
WHERE 
--Exclude deleted databases
DB.DEL_DATE is null
--and LOWER(DB.DATABASE_NAME) is not null
AND PAR.PARAM_VALUE IS NULL
--and DB.DATABASE_NAME='standin1'
And (TRUNC(par.DATE_COLLECTED) is null or TRUNC(par.DATE_COLLECTED)=(SELECT MAX(TRUNC(DATE_COLLECTED)) from ACS_DB_PARAM_HIST where PARAM_NAME='spfile'))
ORDER BY DB.HOST_NAME, LOWER(DB.DATABASE_NAME);

--multilines string parameters (all of them are mentioned in the WHERE clause of the collector query)
SELECT DBLINK_NAME "target name",PAR.PARAM_NAME,COUNT(*) CNT, 
 MIN(PAR.SPPARAM_SID) SPPARAM_SID_1, 
 case when min(par.SPPARAM_SID)<> max(par.SPPARAM_SID) then max(par.SPPARAM_SID) end spparam_sid_2
FROM ACS_DB_INSTANCE DB  JOIN ACS_DB_PARAM_HIST PAR ON PAR.INST_ID=DB.ID
WHERE TRUNC(PAR.DATE_COLLECTED)=(SELECT MAX(TRUNC(DATE_COLLECTED)) FROM ACS_DB_PARAM_HIST WHERE PARAM_NAME='spfile')
--and dblink_name='oka_inquiry'
GROUP BY DBLINK_NAME,PAR.PARAM_NAME
HAVING COUNT(*)>1
ORDER BY 2,3;

--select * from v$spparameter@oka_inquiry where name='db_cache_size';
--Parameters for running instance differ from those specified in spfile
SELECT DB.HOST_NAME "host name", DBLINK_NAME "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE,PAR.PARAM_ISMODIFIED, PAR.SPPARAM_ISSPECIFIED, PAR.PARAM_update_comment, DATE_COLLECTED
FROM ACS_DB_INSTANCE DB  JOIN ACS_DB_PARAM_HIST PAR ON PAR.INST_ID=DB.ID
WHERE 
--Exclude deleted databases
DB.DEL_DATE is null
--and LOWER(DB.DATABASE_NAME) is not null
AND 
(
  (PAR.PARAM_VALUE IS NULL AND PAR.SPPARAM_VALUE IS NOT NULL)
  OR
  (PAR.PARAM_VALUE IS NOT NULL AND PAR.SPPARAM_VALUE IS NULL AND PAR.PARAM_ISDEFAULT<>'TRUE')
  OR 
  (lower(PAR.PARAM_VALUE) <> lower(PAR.SPPARAM_VALUE))
)
AND PAR.PARAM_NAME NOT IN ('parallel_execution_message_size','spfile','log_buffer','sga_max_size','service_names')
AND dblink_name not in ('vetluga_ekp')
AND TRUNC(PAR.DATE_COLLECTED)=(SELECT MAX(TRUNC(DATE_COLLECTED)) FROM ACS_DB_PARAM_HIST WHERE PARAM_NAME='spfile')
ORDER BY DB.HOST_NAME, LOWER(DB.DATABASE_NAME),PAR.PARAM_NAME;

--List of modified parameters (PARAM_ISMODIFIED='MODIFIED')
SELECT DB.HOST_NAME "host name", DBLINK_NAME "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE,PAR.PARAM_ISMODIFIED,PAR.PARAM_ISDEFAULT, PAR.SPPARAM_ISSPECIFIED, PAR.PARAM_update_comment, DATE_COLLECTED
FROM ACS_DB_INSTANCE DB  JOIN ACS_DB_PARAM_HIST PAR ON PAR.INST_ID=DB.ID
WHERE 
--Exclude deleted databases
DB.DEL_DATE IS NULL
AND PARAM_ISMODIFIED='MODIFIED'
AND NVL(lower(PAR.PARAM_VALUE),'aaa') <> NVL(lower(PAR.SPPARAM_VALUE),'aaa')
AND TRUNC(PAR.DATE_COLLECTED)=(SELECT MAX(TRUNC(DATE_COLLECTED)) FROM ACS_DB_PARAM_HIST WHERE PARAM_NAME='spfile')
AND PAR.PARAM_NAME NOT IN ('service_names')
ORDER BY DB.HOST_NAME, LOWER(DB.DATABASE_NAME),PAR.PARAM_NAME;

-- parameter report for parameter '_trace_files_public' not specified in spfile
select par.DATE_COLLECTED, DB.HOST_NAME "host name", 
  --dblink_name "target name", LOWER(DB.DATABASE_NAME) "database name",
  DB.INSTANCE_NAME "Instance name",
  PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE 
from ACS_DB_INSTANCE db  left join ACS_DB_PARAM_HIST par on par.INST_ID=db.ID
and PAR.PARAM_NAME='_trace_files_public'
WHERE 
--Exclude deleted databases
DB.DEL_DATE is null
and (TRUNC(par.DATE_COLLECTED) is null or TRUNC(par.DATE_COLLECTED)=(SELECT MAX(TRUNC(DATE_COLLECTED)) from ACS_DB_PARAM_HIST))
AND (PAR.SPPARAM_VALUE IS NULL OR LOWER(PAR.SPPARAM_VALUE)<>'true')
AND (PAR.PARAM_VALUE IS NULL OR LOWER(PAR.PARAM_VALUE)<>'true')
and LOWER(DB.DATABASE_NAME) is not null
order by DB.HOST_NAME, LOWER(DB.DATABASE_NAME), DB.INSTANCE_NAME;

-- parameter report for values of single parameter 'undo_retention'
select DB.HOST_NAME "host name", dblink_name "target name", DB.DATABASE_NAME "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE,PAR.PARAM_ISMODIFIED,PAR.PARAM_ISDEFAULT, PAR.SPPARAM_ISSPECIFIED,date_collected
from ACS_DB_INSTANCE DB  left join ACS_DB_PARAM_HIST PAR on PAR.INST_ID=DB.id
and PAR.PARAM_NAME like 'commit_wait'
WHERE 
--Exclude deleted databases
DB.DEL_DATE is null
--and LOWER(DB.DATABASE_NAME) is not null
--and LOWER(DB.DATABASE_NAME)='prod'
and (TRUNC(par.DATE_COLLECTED) is null or TRUNC(par.DATE_COLLECTED)=(SELECT MAX(TRUNC(DATE_COLLECTED)) from ACS_DB_PARAM_HIST where PARAM_NAME='commit_wait'))
order by DB.HOST_NAME, LOWER(DB.DATABASE_NAME), dblink_name, PAR.PARAM_NAME;

-- parameter report for values of single parameter (mandatory parameter)
select DB.HOST_NAME "host name", 
--dblink_name "target name", 
LOWER(DB.INSTANCE_NAME) "Instance name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE,date_collected
FROM ACS_DB_INSTANCE DB  JOIN ACS_DB_PARAM_HIST PAR ON PAR.INST_ID=DB.ID
and PAR.PARAM_NAME like 'thread'
WHERE 
--Exclude deleted databases
DB.DEL_DATE is null
and LOWER(DB.DATABASE_NAME) is not null
--and PAR.PARAM_VALUE='TRUE'
and (TRUNC(par.DATE_COLLECTED) is null or TRUNC(par.DATE_COLLECTED)=(SELECT MAX(TRUNC(DATE_COLLECTED)) from ACS_DB_PARAM_HIST where PARAM_NAME='db_files'))
order by PAR.PARAM_VALUE  desc, DB.HOST_NAME, "Instance name";

-- parameter report for values of single parameter (optional parameter)
select db.id,DB.HOST_NAME "host name", 
--dblink_name "target name", 
LOWER(DB.INSTANCE_NAME) "Instance name",
(SELECT PAR.PARAM_VALUE FROM ACS_DB_PARAM_HIST PAR WHERE PAR.INST_ID=DB.ID 
AND PARAM_NAME='_highthreshold_undoretention'
and par.DATE_COLLECTED=(SELECT MAX(DATE_COLLECTED) from ACS_DB_PARAM_HIST where INST_ID=DB.id and PARAM_NAME='_highthreshold_undoretention')) "Parameter value",
(SELECT PAR.SPPARAM_VALUE FROM ACS_DB_PARAM_HIST PAR WHERE PAR.INST_ID=DB.ID 
AND PARAM_NAME='_highthreshold_undoretention'
and par.DATE_COLLECTED=(SELECT MAX(DATE_COLLECTED) from ACS_DB_PARAM_HIST where INST_ID=DB.id and  PARAM_NAME='_highthreshold_undoretention')) "spfile parameter value",
(SELECT MAX(TRUNC(DATE_COLLECTED)) from ACS_DB_PARAM_HIST  PAR where PAR.INST_ID=DB.id AND PARAM_NAME='control_files') date_collected
from ACS_DB_INSTANCE DB  
WHERE 
--Exclude deleted databases
DB.DEL_DATE is null
AND LOWER(DB.DATABASE_NAME) IS NOT NULL
order by "Parameter value"  desc nulls last, DB.HOST_NAME, "Instance name";


-- parameter report for values of 2 parameters
with par1 as (
select DB.HOST_NAME "host name", dblink_name "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE 
from ACS_DB_INSTANCE DB  join ACS_DB_PARAM_HIST PAR on PAR.INST_ID=DB.id
and PAR.PARAM_NAME='sessions'
AND TRUNC(par.DATE_COLLECTED)=(select max(trunc(date_collected)) from ACS_DB_PARAM_HIST where PARAM_NAME='sessions')
WHERE 
DB.DEL_DATE is null
and LOWER(DB.DATABASE_NAME) is not null
order by TO_NUMBER(PARAM_VALUE) desc, DB.HOST_NAME, LOWER(DB.DATABASE_NAME)),
par2 as (
select DB.HOST_NAME "host name", dblink_name "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE 
from ACS_DB_INSTANCE DB  join ACS_DB_PARAM_HIST PAR on PAR.INST_ID=DB.id
and PAR.PARAM_NAME='processes'
AND TRUNC(par.DATE_COLLECTED)=(select max(trunc(date_collected)) from ACS_DB_PARAM_HIST where PARAM_NAME='processes')
WHERE 
DB.DEL_DATE is null
and LOWER(DB.DATABASE_NAME) is not null
order by TO_NUMBER(PARAM_VALUE) desc, DB.HOST_NAME, LOWER(DB.DATABASE_NAME)
)
select NVL(PAR1."host name",PAR2."host name") "host name",
NVL(PAR1."database name",PAR2."database name") "database name",
PAR1.PARAM_VALUE "sessions value",
PAR2.PARAM_VALUE "processes value",
to_number(PAR1.PARAM_VALUE)/to_number(PAR2.PARAM_VALUE) "Ratio"
from PAR1 full outer join PAR2 on PAR1."target name"=PAR2."target name"
order by to_number("processes value") desc;


-- compare parameters report for latest and previous collection
with dt as
(
SELECT DATE_COLL FROM
(
SELECT DISTINCT TRUNC(DATE_COLLECTED) DATE_COLL FROM ACS_DB_PARAM_HIST WHERE PARAM_NAME='processes' ORDER BY DATE_COLL desc nulls last
) where rownum<=5  --Number of last collections
),
PARAMS AS
(
  SELECT TRUNC(P2.DATE_COLLECTED) DATE_COLLECTED,
        P2.PARAM_NAME,
        P2.INST_ID,
        RTRIM(XMLAGG(XMLELEMENT(C,P2.PARAM_VALUE|| ',') ORDER BY P2.PARAM_VALUE).EXTRACT('//text()'),',') PARAM_VALUE,
        RTRIM(XMLAGG(XMLELEMENT(C,P2.SPPARAM_VALUE|| ',') ORDER BY P2.SPPARAM_VALUE).EXTRACT('//text()'),',') SPPARAM_VALUE
  FROM ACS_DB_PARAM_HIST P2  
  WHERE 
      P2.PARAM_ISDEFAULT IS NOT NULL --excluding UDM stored as a parameter in ACS_DB_PARAM_HIST table
  AND TRUNC(P2.DATE_COLLECTED) IN (SELECT DATE_COLL FROM DT)
  GROUP BY TRUNC(P2.DATE_COLLECTED), P2.PARAM_NAME,P2.INST_ID
  ORDER BY DATE_COLLECTED DESC,PARAM_NAME
),
params2 as
(
SELECT 
  DATE_COLLECTED,
  INST_ID,
  PARAM_NAME,
  PARAM_VALUE "Param value at collection date",
  LAG(PARAM_VALUE,1) OVER (PARTITION BY INST_ID,PARAM_NAME ORDER BY DATE_COLLECTED DESC) "Param value changed to",
  LAG(DATE_COLLECTED,1) over (partition by INST_ID,param_name order by DATE_COLLECTED desc) "Param value changed at"
--  PARAM_NAME,
--  PARAM_VALUE "Param value at collection date",
--  LAG(PARAM_VALUE,1) OVER (PARTITION BY INST_ID,PARAM_NAME ORDER BY DATE_COLLECTED DESC) "Param value changed to",
--  LAG(DATE_COLLECTED,1) over (partition by INST_ID,param_name order by DATE_COLLECTED desc) "Param value changed at"
FROM 
  PARAMS
)
SELECT DATE_COLLECTED,
       db.dblink_name "target name", 
       DB.HOST_NAME "host name", 
       LOWER(DB.DATABASE_NAME) "database name",
       case when LOWER(DB.instance_NAME)<> LOWER(DB.DATABASE_NAME) then LOWER(DB.instance_NAME) end "instance name",
       PARAM_NAME,
      "Param value at collection date",
      "Param value changed to",
      "Param value changed at"
FROM PARAMS2 JOIN ACS_DB_INSTANCE DB ON PARAMS2.INST_ID=DB.ID
WHERE lower(NVL("Param value at collection date",'1')) <> lower(NVL("Param value changed to",'1'))
AND "Param value changed at" IS NOT NULL
and PARAM_NAME<>'service_names'
ORDER BY db.dblink_name, "Param value changed at" DESC, DATE_COLLECTED DESC NULLS LAST, PARAM_NAME;

select 
  --DB.HOST_NAME "host name", 
  dblink_name "target name", 
  --LOWER(DB.DATABASE_NAME) "database name",
  PAR_C.PARAM_NAME,
  PAR_C.PARAM_VALUE "Current value",
  PAR_p.PARAM_VALUE "Prev value",
  PAR_C.SPPARAM_VALUE "spfile value",
  PAR_p.SPPARAM_VALUE "Prev spfile value",
  par_c.date_collected "Last collected",
  par_p.date_collected "Prev collected"
from ACS_DB_INSTANCE db join dt on 1=1
   LEFT JOIN ACS_DB_PARAM_HIST par_c on par_c.INST_ID=db.ID and TRUNC(par_c.DATE_COLLECTED)=dt.last_coll
   FULL OUTER JOIN ACS_DB_PARAM_HIST par_p on par_p.INST_ID=db.ID and TRUNC(par_p.DATE_COLLECTED)=dt.prev_coll And par_p.param_name=par_c.param_name
WHERE 
--Exclude deleted databases
DB.DEL_DATE IS NULL
AND PAR_C.PARAM_NAME NOT IN ('local_listener', 'event', 'control_files', 'service_names', 'utl_file_dir', 'service_names')
and LOWER(DB.DATABASE_NAME) is not null
AND UPPER(NVL(PAR_C.PARAM_VALUE,'null'))<>UPPER(NVL(PAR_P.PARAM_VALUE,'null'))
AND PAR_C.PARAM_ISDEFAULT IS NOT NULL --excluding UDM stored as a parameter in ACS_DB_PARAM_HIST table
AND PAR_P.PARAM_ISDEFAULT IS NOT NULL --excluding UDM stored as a parameter in ACS_DB_PARAM_HIST table
order by DB.HOST_NAME, LOWER(DB.DATABASE_NAME), dblink_name, PAR_C.PARAM_NAME;


-- compare parameter values report for 2 databases
with dt as
(
select
(SELECT MAX(TRUNC(DATE_COLLECTED)) FROM ACS_DB_PARAM_HIST WHERE PARAM_NAME='processes') LAST_COLL
FROM DUAL),
PAR1 AS 
(
  SELECT P1.PARAM_NAME,
        RTRIM(XMLAGG(XMLELEMENT(C,P1.PARAM_VALUE|| ',') ORDER BY P1.PARAM_VALUE).EXTRACT('//text()'),',') PARAM_VALUE,
        RTRIM(XMLAGG(XMLELEMENT(C,P1.SPPARAM_VALUE|| ',') ORDER BY P1.SPPARAM_VALUE).EXTRACT('//text()'),',') SPPARAM_VALUE
  FROM ACS_DB_PARAM_HIST P1 JOIN ACS_DB_INSTANCE I1 ON I1.ID=P1.INST_ID JOIN DT ON DT.LAST_COLL=TRUNC(P1.DATE_COLLECTED)
  WHERE I1.INSTANCE_NAME='cardway1'
  AND P1.PARAM_ISDEFAULT IS NOT NULL --excluding UDM stored as a parameter in ACS_DB_PARAM_HIST table
  GROUP BY P1.PARAM_NAME
),
PAR2 AS 
(
  SELECT P2.PARAM_NAME,
        RTRIM(XMLAGG(XMLELEMENT(C,P2.PARAM_VALUE|| ',') ORDER BY P2.PARAM_VALUE).EXTRACT('//text()'),',') PARAM_VALUE,
        RTRIM(XMLAGG(XMLELEMENT(C,P2.SPPARAM_VALUE|| ',') ORDER BY P2.SPPARAM_VALUE).EXTRACT('//text()'),',') SPPARAM_VALUE
  FROM ACS_DB_PARAM_HIST P2 JOIN ACS_DB_INSTANCE I2 ON I2.ID=P2.INST_ID JOIN DT ON DT.LAST_COLL=TRUNC(P2.DATE_COLLECTED)
  WHERE I2.INSTANCE_NAME='cardway2'
  AND P2.PARAM_ISDEFAULT IS NOT NULL --excluding UDM stored as a parameter in ACS_DB_PARAM_HIST table
  GROUP BY P2.PARAM_NAME
)
SELECT 
  NVL(PAR1.PARAM_NAME,PAR2.PARAM_NAME) "Parameter",
  CASE WHEN UPPER(NVL(PAR1.PARAM_VALUE,'null'))<>UPPER(NVL(PAR2.PARAM_VALUE,'null')) AND UPPER(NVL(PAR1.SPPARAM_VALUE,'null'))<>UPPER(NVL(PAR2.SPPARAM_VALUE,'null')) THEN 'running and spfile'
       WHEN UPPER(NVL(PAR1.PARAM_VALUE,'null'))<>UPPER(NVL(PAR2.PARAM_VALUE,'null')) THEN 'running'
       WHEN UPPER(NVL(PAR1.SPPARAM_VALUE,'null'))<>UPPER(NVL(PAR2.SPPARAM_VALUE,'null')) THEN 'spfile'
       ELSE 'same'
  END "Difference in",
  PAR1.PARAM_VALUE "Running values, instance1",
  PAR2.PARAM_VALUE "Running values, instance2",
  PAR1.SPPARAM_VALUE "spfile values, instance1",
  PAR2.SPPARAM_VALUE "spfile values, instance2"
FROM PAR1
    FULL OUTER JOIN PAR2 on PAR1.PARAM_NAME=PAR2.PARAM_NAME 
WHERE 
 (
  UPPER(NVL(PAR1.PARAM_VALUE,'null'))<>UPPER(NVL(PAR2.PARAM_VALUE,'null'))
 OR 
  UPPER(NVL(PAR1.SPPARAM_VALUE,'null'))<>UPPER(NVL(PAR2.SPPARAM_VALUE,'null'))
 )
AND 
 NVL(PAR1.PARAM_NAME,PAR2.PARAM_NAME) Not in ('control_files',
                                                  'background_dump_dest',
                                                  'core_dump_dest',
                                                  'audit_file_dest',
                                                  'dg_broker_config_file1',
                                                  'dg_broker_config_file2',
                                                  'diagnostic_dest',
                                                  'local_listener',
                                                  'user_dump_dest')
And  NVL(PAR1.PARAM_VALUE,PAR2.PARAM_VALUE) not like 'SCHEDULER[%]:%PLAN'
order by NVL(PAR1.PARAM_NAME,PAR2.PARAM_NAME);



-- parameter change history for single instance and single parameter
  SELECT trunc(p2.date_collected) date_collected,
        P2.PARAM_NAME,
        P2.PARAM_VALUE
        --RTRIM(XMLAGG(XMLELEMENT(C,P2.SPPARAM_VALUE|| ',') ORDER BY P2.SPPARAM_VALUE).EXTRACT('//text()'),',') SPPARAM_VALUE
  FROM ACS_DB_PARAM_HIST P2 JOIN ACS_DB_INSTANCE I2 ON I2.ID=P2.INST_ID 
  WHERE I2.INSTANCE_NAME='ekp'
  AND P2.param_name='db_block_checking'
  AND P2.PARAM_ISDEFAULT IS NOT NULL --excluding UDM stored as a parameter in ACS_DB_PARAM_HIST table
  order by date_collected desc,param_name;


-- parameter change history for single instance
WITH PARAMS AS
(
  SELECT trunc(p2.date_collected) date_collected,
        P2.PARAM_NAME,
        RTRIM(XMLAGG(XMLELEMENT(C,P2.PARAM_VALUE|| ',') ORDER BY P2.PARAM_VALUE).EXTRACT('//text()'),',') PARAM_VALUE,
        RTRIM(XMLAGG(XMLELEMENT(C,P2.SPPARAM_VALUE|| ',') ORDER BY P2.SPPARAM_VALUE).EXTRACT('//text()'),',') SPPARAM_VALUE
  FROM ACS_DB_PARAM_HIST P2 JOIN ACS_DB_INSTANCE I2 ON I2.ID=P2.INST_ID 
  WHERE I2.DBLINK_NAME='kagera_ekp'
  AND P2.param_name='db_block_checking'
  AND P2.PARAM_ISDEFAULT IS NOT NULL --excluding UDM stored as a parameter in ACS_DB_PARAM_HIST table
  GROUP BY P2.PARAM_NAME,TRUNC(P2.DATE_COLLECTED)
  order by date_collected desc,param_name
),
params2 as
(
SELECT 
  DATE_COLLECTED,
  PARAM_NAME,
  PARAM_VALUE "Param value at collection date",
  LAG(PARAM_VALUE,1) OVER (PARTITION BY PARAM_NAME ORDER BY DATE_COLLECTED DESC) "Param value changed to",
  LAG(DATE_COLLECTED,1) over (partition by param_name order by DATE_COLLECTED desc) "Param value changed at"
FROM 
  PARAMS
)
SELECT DATE_COLLECTED,
       PARAM_NAME,
      "Param value at collection date",
      "Param value changed to",
      "Param value changed at"
FROM PARAMS2
WHERE NVL("Param value at collection date",'1') <> NVL("Param value changed to",'1')
order by DATE_COLLECTED desc, "Param value changed at" desc nulls last, PARAM_NAME;

-- parameter report for values of single parameter 'undo_retention'
select DB.HOST_NAME "host name", dblink_name "target name", LOWER(DB.DATABASE_NAME) "database name",PAR.PARAM_NAME,PAR.PARAM_VALUE,PAR.SPPARAM_VALUE,date_collected
FROM ACS_DB_INSTANCE DB  LEFT JOIN ACS_DB_PARAM_HIST PAR ON PAR.INST_ID=DB.ID
and PAR.PARAM_NAME like 'undo_retention'
WHERE 
--Exclude deleted databases
--DB.DEL_DATE is null
--and LOWER(DB.DATABASE_NAME) is not null
(TRUNC(PAR.DATE_COLLECTED) IS NULL OR TRUNC(PAR.DATE_COLLECTED)=(SELECT MAX(TRUNC(DATE_COLLECTED)) FROM ACS_DB_PARAM_HIST WHERE PARAM_NAME='undo_retention'))
order by DB.HOST_NAME, LOWER(DB.DATABASE_NAME);