
--Prerequsite: run the procedure for database link creation

------
----- Collecting password security settings for all profiles in all databases
-----
set serveroutput on timing on
DECLARE


--List of databases
CURSOR DBNAME_CUR 
  IS 
Select distinct ID, database_name,database_name || '_' || host_name dblink_name, nvl(tns_service_name,database_name) tns_service_name, Status1,Version
from AHJELMQV.ORACLEDB_MBAZGOUT db
WHERE 
--exclude all except databases
INSTANCE_TYPE='DB' 
--exclude deleted databases
AND DEL_DATE is null
--exclude standby databases
AND (db.STATUS2 is null or db.STATUS2<>'Standby')
--exclude non-billed databases
AND (BILLING_CATEGORY is null or BILLING_CATEGORY<>'None')
--exclude databases already collected today
AND not exists (select 1 from AHJELMQV.ORACLEDBS_PROFILES where id_mbazgout=db.ID and trunc(DATE_COLLECTED)=trunc(sysdate));


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


v_cur  number;   
v_ret number; 

BEGIN
OPEN DBNAME_CUR; 
LOOP 
  FETCH DBNAME_CUR INTO DBNAME_rec; 
  EXIT WHEN DBNAME_CUR%NOTFOUND; 
     begin
        
        v_link_name := DBNAME_rec.dblink_name;
         dbms_output.PUT_LINE(v_link_name);
        -- Retrieve object list including all roles 
        if Substr(DBNAME_rec.Version,1,3) not in ('8.1','9.0') then
            execute immediate 'INSERT INTO AHJELMQV.ORACLEDBS_PROFILES (profile, PASSWORD_GRACE_TIME,
                PASSWORD_LOCK_TIME,
                PASSWORD_VERIFY_FUNCTION,
                PASSWORD_REUSE_MAX,
                PASSWORD_REUSE_TIME,
                PASSWORD_LIFE_TIME,
                FAILED_LOGIN_ATTEMPTS,
                COUNT_USERS,
                password_length,
                ID_MBAZGOUT) select pr.profile,
                PASSWORD_GRACE_TIME.limit PASSWORD_GRACE_TIME,
                PASSWORD_LOCK_TIME.limit PASSWORD_LOCK_TIME,
                PASSWORD_VERIFY_FUNCTION.limit PASSWORD_VERIFY_FUNCTION,
                PASSWORD_REUSE_MAX.limit PASSWORD_REUSE_MAX,
                PASSWORD_REUSE_TIME.limit PASSWORD_REUSE_TIME,
                PASSWORD_LIFE_TIME.limit PASSWORD_LIFE_TIME,
                FAILED_LOGIN_ATTEMPTS.limit FAILED_LOGIN_ATTEMPTS,
                (SELECT COUNT(decode (username,''XS$NULL'',null,username)) FROM dba_users@' || v_link_name || '  WHERE profile=pr.profile) COUNT_USERS,
                (select regexp_replace(s.text,''[^[:digit:]]'','''') text from
                    (select profile,limit 
                    from dba_profiles@' || v_link_name || ' p 
                    where p.resource_name=''PASSWORD_VERIFY_FUNCTION'') p 
                    join dba_source@' || v_link_name || ' s on s.owner=''SYS'' and  s.name=p.limit
                    where upper(text) like ''%IF%LENGTH(PASSWORD)%<%'' AND upper(text) not like ''%OLD_PASSWORD%''
                    and p.profile=pr.profile
                ) password_length,
                ' || to_char(DBNAME_rec.ID) || '
                from
                (select distinct profile from dba_profiles@' || v_link_name || '  
                ) pr
                join
                ( 
                select LIMIT,profile from dba_profiles@' || v_link_name || '  WHERE RESOURCE_NAME=''PASSWORD_GRACE_TIME''
                ) PASSWORD_GRACE_TIME on  PASSWORD_GRACE_TIME.profile=pr.profile
                join
                (
                select LIMIT,profile  from dba_profiles@' || v_link_name || '  WHERE RESOURCE_NAME=''PASSWORD_LOCK_TIME''
                ) PASSWORD_LOCK_TIME on PASSWORD_LOCK_TIME.profile=pr.profile
                join
                (select LIMIT,profile  from dba_profiles@' || v_link_name || '  WHERE RESOURCE_NAME=''PASSWORD_VERIFY_FUNCTION''
                ) PASSWORD_VERIFY_FUNCTION on PASSWORD_VERIFY_FUNCTION.profile=pr.profile
                join
                (select LIMIT,profile  from dba_profiles@' || v_link_name || '  WHERE RESOURCE_NAME=''PASSWORD_REUSE_MAX''
                ) PASSWORD_REUSE_MAX on PASSWORD_REUSE_MAX.profile=pr.profile
                join
                (select LIMIT,profile  from dba_profiles@' || v_link_name || '  WHERE RESOURCE_NAME=''PASSWORD_REUSE_TIME''
                ) PASSWORD_REUSE_TIME on PASSWORD_REUSE_TIME.profile=pr.profile
                join
                (select LIMIT,profile  from dba_profiles@' || v_link_name || '  WHERE RESOURCE_NAME=''PASSWORD_LIFE_TIME''
                ) PASSWORD_LIFE_TIME on PASSWORD_LIFE_TIME.profile=pr.profile
                join
                (select LIMIT,profile  from dba_profiles@' || v_link_name || '  WHERE RESOURCE_NAME=''FAILED_LOGIN_ATTEMPTS''
                ) FAILED_LOGIN_ATTEMPTS on FAILED_LOGIN_ATTEMPTS.profile=pr.profile ';
         
         end if;    
        COMMIT;
     
     EXCEPTION 
       when OTHERS then 
       v_error_msg := SQLERRM;
       -- log error to value_char field
       INSERT INTO AHJELMQV.ORACLEDBS_OBJECTS (ID_MBAZGOUT, NOTE, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_error_msg , SYSDATE);
       dbms_output.PUT_LINE(v_error_msg);
       commit;
      
     end;          
END LOOP;
 
CLOSE DBNAME_CUR; 
end;
/

-- how many databases was collected
select 
(select 
    count(distinct ID_MBAZGOUT) from AHJELMQV.ORACLEDBS_PROFILES where trunc(DATE_COLLECTED)=TRUNC(SYSDATE)) "Collected profiles",
(select count(distinct ID) from 
    AHJELMQV.ORACLEDB_MBAZGOUT db 
    WHERE 
    --exclude all except databases
    INSTANCE_TYPE='DB' 
    --exclude deleted databases
    AND DEL_DATE is null
    --exclude not-billed
    AND (BILLING_CATEGORY is null or BILLING_CATEGORY<>'None')
    --exclude Standby
    AND (STatus2 is null or Status2<>'Standby')) "Total DB count"
from dual;

--Collection failed/missed
select * from 
    AHJELMQV.ORACLEDB_MBAZGOUT db 
    WHERE 
    --exclude all except databases
    INSTANCE_TYPE='DB' 
    --exclude deleted databases
    AND DEL_DATE is null
    --exclude Standby
    AND (STatus2 is null or Status2<>'Standby')
    --exclude not-billed
    AND (BILLING_CATEGORY is null or BILLING_CATEGORY<>'None')
    and not exists (select 1 from AHJELMQV.ORACLEDBS_PROFILES where trunc(DATE_COLLECTED)=TRUNC(SYSDATE) and ID_MBAZGOUT=db.id);
    

--collection errors
select db.database_name,obj.Note, DATE_COLLECTED  from AHJELMQV.ORACLEDBS_OBJECTS obj 
join AHJELMQV.ORACLEDB_MBAZGOUT db on obj.id_mbazgout=db.id where TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE)
AND obj.Note like 'ORA%'
order by date_collected desc;

-- report
select 
    lower(db.database_name) dbname,
    UPPER(db.host_name) host_name,
    db.Status1 "Database status",
    pr.profile "Profile",
    pr.PASSWORD_GRACE_TIME,
    pr.PASSWORD_LOCK_TIME,
    pr.PASSWORD_VERIFY_FUNCTION,
    pr.PASSWORD_REUSE_MAX,
    pr.PASSWORD_REUSE_TIME,
    pr.PASSWORD_LIFE_TIME,
    pr.FAILED_LOGIN_ATTEMPTS,
    pr.password_length,
    pr.COUNT_USERS
from 
    AHJELMQV.ORACLEDB_MBAZGOUT db 
    left join AHJELMQV.ORACLEDBS_PROFILES pr on pr.ID_MBAZGOUT=db.ID --AND trunc(acc.DATE_COLLECTED)=TRUNC(SYSDATE)
WHERE 
--exclude all except databases
INSTANCE_TYPE='DB' 
--exclude deleted databases
AND DEL_DATE is null
--exclude Standby
AND (STatus2 is null or Status2<>'Standby')
--exclude Non-billable
AND (Billing_Category is null or Billing_Category<>'None')
-- only last collection
AND trunc(pr.DATE_COLLECTED)=(SELECT TRUNC(MAX(p2.DATE_COLLECTED))  from AHJELMQV.ORACLEDBS_PROFILES p2 where p2.id_mbazgout=pr.id_mbazgout)
--and db.host_name like '%003%'
--and acc.UserName is null
and lower(db.database_name) like 'dpcdb%'
--AND lower(db.database_name) in (select lower(dbname) FROM AHJELMQV.oracledbs where lower(ITAM)='rbrow619')
order by UPPER(db.host_name), lower(db.database_name), pr.profile;

--ERrors
select 
    lower(db.database_name) dbname,
    UPPER(db.host_name) host_name,
    obj.Note
from 
    AHJELMQV.ORACLEDB_MBAZGOUT db 
    join AHJELMQV.ORACLEDBS_OBJECTS obj on obj.ID_MBAZGOUT=db.ID AND TRUNC(obj.DATE_COLLECTED)=TRUNC(SYSDATE)
WHERE 
--exclude all except databases
INSTANCE_TYPE='DB' 
--exclude deleted databases
AND DEL_DATE is null
--exclude not-billed
AND (BILLING_CATEGORY is null or BILLING_CATEGORY<>'None')
--exclude Standby
AND (STatus2 is null or Status2<>'Standby')
order by UPPER(db.host_name), lower(db.database_name), obj.object_name,obj.object_type;


-- password length <8
select 
    lower(db.database_name) "Database",
    db.Application "Application",
    lower(db.host_name) "Host",
    db.Status1 "Database status",
    pr.PASSWORD_VERIFY_FUNCTION,
    pr.password_length "Min password length",
    COUNT(DISTINCT profile) "Num of profiles affected",
    SUM(pr.COUNT_USERS) "Num of affected users"
from 
    AHJELMQV.ORACLEDB_MBAZGOUT db 
    left join AHJELMQV.ORACLEDBS_PROFILES pr on pr.ID_MBAZGOUT=db.ID --AND trunc(acc.DATE_COLLECTED)=TRUNC(SYSDATE)
WHERE 
--exclude all except databases
INSTANCE_TYPE='DB' 
--exclude deleted databases
AND DEL_DATE is null
--exclude Standby
AND (STatus2 is null or Status2<>'Standby')
--exclude Non-billable
AND (Billing_Category is null or Billing_Category<>'None')
-- only last collection
AND trunc(pr.DATE_COLLECTED)=(SELECT TRUNC(MAX(DATE_COLLECTED))  from AHJELMQV.ORACLEDBS_PROFILES)
--and db.host_name like '%003%'
--and acc.UserName is null
--and lower(db.database_name)='dpbdmp'
--AND lower(db.database_name) in (select lower(dbname) FROM AHJELMQV.oracledbs where lower(ITAM)='rbrow619')
and pr.password_length<8
group by     lower(db.database_name),
    db.Application,
    lower(db.host_name) ,
    db.Status1,
    pr.PASSWORD_VERIFY_FUNCTION,
    pr.password_length
order by db.Application, lower(db.database_name);
