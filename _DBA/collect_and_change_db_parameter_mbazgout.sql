--create database link dptst11t connect to mbazgout identified by password5 using 'dptst11t';
create or replace synonym remote_dbms_sql for dbms_sql@dptst11t;

------
----- Collecting database size for databases from Mikhail's table
----- 
set serveroutput on
DECLARE


--List of databases
CURSOR DBNAME_CUR 
  IS 
Select distinct ID, database_name,NVL(dblink_name,database_name) dblink_name, nvl(tns_service_name,database_name) tns_service_name, Status1
from AHJELMQV.ORACLEDB_MBAZGOUT db
WHERE 
--exclude all except databases
INSTANCE_TYPE='DB' 
--exclude deleted databases
AND DEL_DATE is null
--exclude non-billing
AND (BILLING_CATEGORY is null or BILLING_CATEGORY<>'None');

DBNAME_rec  DBNAME_CUR%ROWTYPE;                   

TYPE cursor_ref IS REF CURSOR;
c1 cursor_ref;
v_error_msg varchar2(4000);
v_sqlcode number;
v_link_name Varchar2(500);
v_tmp_num number;
v_tmp_char Varchar2(4000);
v_tmp_char1 Varchar2(4000);
v_tmp_char2 Varchar2(4000);
v_tmp_char3 Varchar2(4000);

v_cur  number;   
v_ret number; 

BEGIN
OPEN DBNAME_CUR; 
LOOP 
  FETCH DBNAME_CUR INTO DBNAME_rec; 
  EXIT WHEN DBNAME_CUR%NOTFOUND; 
     begin
        --DElete data collected today.
        DELETE FROM AHJELMQV.ORACLEDBS_PARAMS WHERE ID_MBAZGOUT=DBNAME_rec.ID AND PARAM_NAME IN ('type of parameter file','is default parallel_max_servers','parallel_max_servers','parallel_max_servers before','parallel_max_servers after','is default parallel_max_servers after') AND DATE_COLLECTED=TRUNC(SYSDATE);
        
        v_link_name := DBNAME_rec.dblink_name;
       --safe removal of dblink
       begin
            EXECUTE IMMEDIATE 'drop database link ' || v_link_name;
       EXCEPTION when others then 
        null;
       end;
        -- Create database link
        begin
            EXECUTE IMMEDIATE 'create database link ' || v_link_name || ' connect to mbazgout identified by password2015 using ''' || DBNAME_rec.tns_service_name || '.volvo''';
        exception when OTHERS then 
            null;
        end;
        -- test the database link
        BEGIN
            OPEN c1 FOR 'select * from dual@' || v_link_name;
            close c1;
         EXCEPTION 
           when OTHERS then 
           v_sqlcode := SQLCODE;
           v_error_msg := SQLERRM;
           --if error is ORA-2085 then recreate database link with different name
           if v_sqlcode=-2085 then
                CLOSE C1;
               --safe removal of dblink
               begin
                    EXECUTE IMMEDIATE 'drop database link ' || v_link_name;
               EXCEPTION when others then 
                null;
               end;
                -- Create database link with new name
                v_link_name := SUBSTR(v_error_msg,INSTR(v_error_msg,'connects to ')+12,100);
                begin
                    EXECUTE IMMEDIATE 'create database link ' || v_link_name || ' connect to mbazgout identified by password2015 using ''' || DBNAME_rec.tns_service_name || '.volvo''';
                exception when OTHERS then 
                    null;
                end; 
                UPDATE AHJELMQV.ORACLEDB_MBAZGOUT SET DBLINK_NAME=v_link_name WHERE ID=DBNAME_rec.ID;
                COMMIT;
           else 
                raise;                    
           end if; 
        END;

         
        -- Retrieve type of parameter file

        OPEN c1 FOR 'select decode(value,null,''init'',''spfile'') initfile from v$parameter@' || v_link_name || ' where name=''spfile''';
        FETCH C1 into v_tmp_char1;
        INSERT INTO AHJELMQV.ORACLEDBS_PARAMS (ID_MBAZGOUT, VALUE_CHAR, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_tmp_char1, 'type of parameter file',TRUNC(SYSDATE));
        CLOSE C1;

        OPEN c1 FOR 'select isdefault from v$parameter@' || v_link_name || ' where name=''parallel_max_servers''';
        FETCH C1 into v_tmp_char2;
        INSERT INTO AHJELMQV.ORACLEDBS_PARAMS (ID_MBAZGOUT, VALUE_CHAR, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_tmp_char2, 'is default parallel_max_servers',TRUNC(SYSDATE));
        CLOSE C1;
        
        OPEN c1 FOR 'select value from v$parameter@' || v_link_name || ' where name=''parallel_max_servers''';
        FETCH C1 into v_tmp_char3;
        INSERT INTO AHJELMQV.ORACLEDBS_PARAMS (ID_MBAZGOUT, VALUE_CHAR, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_tmp_char3, 'parallel_max_servers before',TRUNC(SYSDATE));
        CLOSE C1;
        
        --changing params
        dbms_output.put_Line (v_tmp_char1 || v_tmp_char2|| v_tmp_char3 || DBNAME_rec.Status1);
       
        if v_tmp_char1='spfile' AND v_tmp_char2='TRUE' AND TO_NUMBER(v_tmp_char3)>8 AND DBNAME_rec.Status1<>'Production' then
            --create synonym for remote dbms_sql
            execute immediate 'create or replace synonym remote_dbms_sql for dbms_sql@' || v_link_name;
            begin   
                v_cur := remote_dbms_sql.open_cursor();   
                remote_dbms_sql.parse( v_cur, 'alter system set parallel_max_servers=8 scope=both', dbms_sql.native );   
                v_ret := remote_dbms_sql.execute( v_cur ); 
                dbms_output.put_line( v_ret );   
                remote_dbms_sql.close_cursor( v_cur ); 
             EXCEPTION 
               when OTHERS then 
               v_error_msg := SQLERRM;
               -- log error to value_char field
               INSERT INTO AHJELMQV.ORACLEDBS_PARAMS (ID_MBAZGOUT, VALUE_CHAR, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_error_msg , 'parallel_max_servers after',TRUNC(SYSDATE));
               commit;
               remote_dbms_sql.close_cursor( v_cur ); 
               --safe removal of dblink
               begin
                    EXECUTE IMMEDIATE 'drop database link ' || v_link_name;
               EXCEPTION when others then 
                null;
               end;                
            end; 

        end if;

        OPEN c1 FOR 'select isdefault from v$parameter@' || v_link_name || ' where name=''parallel_max_servers''';
        FETCH C1 into v_tmp_char2;
        INSERT INTO AHJELMQV.ORACLEDBS_PARAMS (ID_MBAZGOUT, VALUE_CHAR, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_tmp_char2, 'is default parallel_max_servers after',TRUNC(SYSDATE));
        CLOSE C1;
        OPEN c1 FOR 'select value from v$parameter@' || v_link_name || ' where name=''parallel_max_servers''';
        FETCH C1 into v_tmp_char3;
        INSERT INTO AHJELMQV.ORACLEDBS_PARAMS (ID_MBAZGOUT, VALUE_NUMBER, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_tmp_char3, 'parallel_max_servers after',TRUNC(SYSDATE));
        CLOSE C1;

        COMMIT;
       --safe removal of dblink
       begin
            EXECUTE IMMEDIATE 'drop database link ' || v_link_name;
       EXCEPTION when others then 
        null;
       end;
      
     EXCEPTION 
       when OTHERS then 
       v_error_msg := SQLERRM;
       -- log error to value_char field
       INSERT INTO AHJELMQV.ORACLEDBS_PARAMS (ID_MBAZGOUT, VALUE_CHAR, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_error_msg , 'type of parameter file',TRUNC(SYSDATE));
       commit;
       --safe removal of dblink
       begin
            EXECUTE IMMEDIATE 'drop database link ' || v_link_name;
       EXCEPTION when others then 
        null;
       end;
       
     end;          
END LOOP;
 
CLOSE DBNAME_CUR; 
end;
/

-- parameter report 'type of parameter file','is default parallel_max_servers','parallel_max_servers'

select 
    lower(db.database_name) dbname,
    UPPER(db.host_name) host_name,
    db.Status1,
    par1.value_char "Param file type",
    par2.value_char "is dflt parallel_max_servers",
    par3.value_char "parallel_max_servers before",
    par4.value_char "parallel_max_servers after",
    par5.value_char "is dflt prll_max_servers after",
    case when db.Status1<>'Production' and  TO_NUMBER( par3.value_char)>8 AND  par2.value_char='TRUE' then
    '. set_sid -i ' || db.database_name || '; sqlplus  -s ''/ as sysdba'' @/lfs/oracle_temp/change_parameter.sql"' 
    end script
    
from 
    AHJELMQV.ORACLEDB_MBAZGOUT db 
    left join AHJELMQV.ORACLEDBS_PARAMS par1 on par1.ID_MBAZGOUT=db.ID AND par1.PARAM_NAME='type of parameter file' AND par1.DATE_COLLECTED=TRUNC(SYSDATE)
    left join AHJELMQV.ORACLEDBS_PARAMS par2 on par2.ID_MBAZGOUT=db.ID AND par2.PARAM_NAME='is default parallel_max_servers' AND par2.DATE_COLLECTED=TRUNC(SYSDATE)
    left join AHJELMQV.ORACLEDBS_PARAMS par3 on par3.ID_MBAZGOUT=db.ID AND par3.PARAM_NAME='parallel_max_servers before' AND par3.DATE_COLLECTED=TRUNC(SYSDATE)  
    left join AHJELMQV.ORACLEDBS_PARAMS par4 on par4.ID_MBAZGOUT=db.ID AND par4.PARAM_NAME='parallel_max_servers after' AND par4.DATE_COLLECTED=TRUNC(SYSDATE)                
    left join AHJELMQV.ORACLEDBS_PARAMS par5 on par5.ID_MBAZGOUT=db.ID AND par5.PARAM_NAME='is default parallel_max_servers after' AND par5.DATE_COLLECTED=TRUNC(SYSDATE)    
WHERE 
--exclude all except databases
INSTANCE_TYPE='DB' 
--exclude deleted databases
AND DEL_DATE is null
--exclude non-billing
AND (BILLING_CATEGORY is null or BILLING_CATEGORY<>'None')
order by UPPER(db.host_name), lower(db.database_name);

----non default database link names
--select host_name,database_name,dblink_name from AHJELMQV.ORACLEDB_MBAZGOUT where dblink_name is not null;

----errors when collecting parameter
--select lower(db.database_name) dbname,UPPER(db.host_name) host_name,par.value_char "Error" ,tns_service_name, dblink_name
--from AHJELMQV.ORACLEDBS_PARAMS par right join AHJELMQV.ORACLEDB_MBAZGOUT db on par.ID_MBAZGOUT=db.ID
--AND par.PARAM_NAME='type of parameter file'
--AND par.DATE_COLLECTED=TRUNC(SYSDATE) 
--WHERE db.INSTANCE_TYPE='DB' and par.value_number is null
--order by lower(db.database_name);
