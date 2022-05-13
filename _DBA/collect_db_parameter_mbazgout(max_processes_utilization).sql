------
----- Collecting database size for databases from Mikhail's table
----- 

DECLARE

--List of databases
CURSOR DBNAME_CUR 
  IS 
Select distinct ID, database_name,NVL(dblink_name,database_name) dblink_name, nvl(tns_service_name,database_name) tns_service_name
from AHJELMQV.ORACLEDB_MBAZGOUT db
WHERE 
--exclued all except databases
INSTANCE_TYPE='DB' 
--exclude deleted databases
AND DEL_DATE is null
AND (BILLING_CATEGORY is null or BILLING_CATEGORY<>'None');
--exclude already collected today
--AND NOT EXISTS (SELECT 1 from AHJELMQV.ORACLEDBS_PARAMS dbp where dbp.id_Mbazgout=db.id and dbp.PARAM_NAME='type of parameter file' AND dbp.DATE_COLLECTED=TRUNC(SYSDATE) and dbp.value_char is not null and dbp.value_char not like '%ORA%');

DBNAME_rec  DBNAME_CUR%ROWTYPE;                   

TYPE cursor_ref IS REF CURSOR;
c1 cursor_ref;
v_error_msg varchar2(4000);
v_sqlcode number;
v_link_name Varchar2(500);
v_tmp_num number;
v_tmp_char Varchar2(4000);

BEGIN
OPEN DBNAME_CUR; 
LOOP 
  FETCH DBNAME_CUR INTO DBNAME_rec; 
  EXIT WHEN DBNAME_CUR%NOTFOUND; 
     begin
        --DElete data collected today.
        DELETE FROM AHJELMQV.ORACLEDBS_PARAMS WHERE ID_MBAZGOUT=DBNAME_rec.ID AND PARAM_NAME IN ('Max_processes_utilization') AND DATE_COLLECTED=TRUNC(SYSDATE);
        
        v_link_name := DBNAME_rec.dblink_name;
        
        -- Retrieve parameter value

        
        OPEN c1 FOR 'select  Round(MAX_UTILIZATION/LIMIT_VALUE*100) Proc_usage_max from v$resource_limit@' || v_link_name || ' where resource_name=''processes''';
        FETCH C1 into v_tmp_num;
        INSERT INTO AHJELMQV.ORACLEDBS_PARAMS (ID_MBAZGOUT, VALUE_NUMBER, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_tmp_num, 'Max_processes_utilization',TRUNC(SYSDATE));
        CLOSE C1;
dbms_output.put_line(ID_MBAZGOUT || ' ' || v_tmp_num);
        COMMIT;
      
     EXCEPTION 
       when OTHERS then 
       v_error_msg := SQLERRM;
       -- log error to value_char field
       INSERT INTO AHJELMQV.ORACLEDBS_PARAMS (ID_MBAZGOUT, VALUE_CHAR, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_error_msg , 'Max_processes_utilization',TRUNC(SYSDATE));
       commit;
       
     end;          
END LOOP;
 
CLOSE DBNAME_CUR; 
end;
/

-- parameter report 'Max_processes_utilization''

select lower(db.database_name) dbname,UPPER(db.host_name) host_name,par.value_number "Max_processes_utilization, %",par.value_char "Error"
 
from AHJELMQV.ORACLEDBS_PARAMS par right join AHJELMQV.ORACLEDB_MBAZGOUT db on par.ID_MBAZGOUT=db.ID
AND par.PARAM_NAME='Max_processes_utilization'
AND par.DATE_COLLECTED=TRUNC(SYSDATE) 
AND par.value_char is not null
WHERE 
--excluded all except databases
INSTANCE_TYPE='DB' 
--exclude deleted databases
AND DEL_DATE is null
AND (BILLING_CATEGORY is null or BILLING_CATEGORY<>'None')
order by par.value_number desc,lower(db.database_name);
