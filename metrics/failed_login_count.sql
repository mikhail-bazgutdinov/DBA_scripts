A-- Count of failed logins from dba_audit_session grouped by username, and return code. 
-- Host names are rolled up to single row
with aud as 
(select trunc(extended_timestamp,'dd') "Date/time", username "Username", userhost, returncode, 
case when returncode=28000 then 'Account is locked' 
when returncode=28001 then 'Password is expired' 
when returncode=1017 then 'Invalid username or password' 
when returncode=1045 then 'User lacks CREATE SESSION privilege' 
end "Error message", count(*) cnt
from dba_audit_session
WHERE RETURNCODE<>0
AND extended_TIMESTAMP>trunc(SYSDATE)-1/24  ---!!!!!! Last hour
group by trunc(extended_timestamp,'dd'), username, userhost, returncode
having count(*)>10
order by trunc(extended_timestamp,'dd') desc ,count(*) desc
)
select "Date/time", "Username", returncode, "Error message", sum(cnt) "Number of login attempts",
RTRIM(XMLAGG(XMLELEMENT(C,userhost || ',') ORDER BY userhost).EXTRACT('//text()'),',') "Client hosts",
case 
  when returncode=28001 then (select account_status || '  - ' || to_char(expiry_date,'dd.mm.yyyy hh24:mi') from dba_users u where u.username=aud."Username") 
  when returncode=28000 then (select account_status || '  - ' || to_char(lock_date,'dd.mm.yyyy hh24:mi') from dba_users u where u.username=aud."Username") 
  when returncode=1045 then (select account_status || '  - ' || case when account_status like '%LOCK%' then to_char(lock_date,'dd.mm.yyyy hh24:mi') when account_status like '%EXPIR%' then to_char(expiry_date,'dd.mm.yyyy hh24:mi') end from dba_users u where u.username=aud."Username") 
  when returncode=1017 then NVL((select account_status from dba_users u where u.username=aud."Username"),'<User does not exist>')
end "Acc status and Exp/lock date",
case 
  when returncode=28001 then (select p.resource_name || '  - ' || p.limit from dba_users u join dba_profiles p on p.PROFILE=u.profile and p.RESOURCE_NAME='PASSWORD_LIFE_TIME' where u.username=aud."Username") 
  when returncode=28000 then (select p.resource_name || '  - ' || p.limit from dba_users u join dba_profiles p on p.PROFILE=u.profile and p.RESOURCE_NAME='FAILED_LOGIN_ATTEMPTS' where u.username=aud."Username") 
  --when returncode=1017 then NVL((select account_status from dba_users u where u.username=aud."Username"),'<User does not exist>')
end "Profile setting"
from aud
group by "Date/time", "Username", returncode, "Error message"
order by "Date/time" desc ,sum(cnt) desc;

-- Count of failed logins grouped by username, host, return code.
--Using sys.aud$ as source of information
select trunc(ntimestamp#,'dd') "Date/time", userid "Username", userhost, returncode, 
case when returncode=28000 then 'Account is locked' 
when returncode=28001 then 'Password is expired' 
when returncode=1017 then 'Invalid username or password' 
end "Error message", count(*) "Number of login attempts"
from sys.aud$
where returncode<>0
and ntimestamp#>sysdate-2
group by trunc(ntimestamp#,'dd'), userid, userhost, returncode
order by trunc(ntimestamp#,'dd') desc ,count(*) desc;

-- Count of failed logins grouped by username, host, return code.
--Using dba_audit_session as source of information
with aud_info as
(select trunc(extended_timestamp,'hh') "Date_time", a.username "Username", userhost, returncode, 
case when returncode=28000 then 'Account is locked' 
when returncode=28001 then 'Password is expired' 
when returncode=1017 then 'Invalid username or password' 
end "Error message", count(*) "Number of login attempts"
from dba_audit_session a
WHERE a.RETURNCODE<>0
AND a.extended_TIMESTAMP>SYSDATE-1  --!!!!!!! Last day
group by trunc(extended_timestamp,'hh'), a.username, userhost, returncode
)
select ai.*,u.lock_date,u.expiry_date from dba_users u,aud_info ai
where ai."Username"=u.username
order by ai."Date_time" desc ,ai."Number of login attempts" desc;


--Find a lock reason in detailed audit logs
select to_char(extended_timestamp,'hh24:mi:ss') "Time", username "Username", userhost, returncode, 
case when returncode=28000 then 'Account is locked' 
when returncode=28001 then 'Password is expired' 
when returncode=1017 then 'Invalid username or password' 
end "Error message"
from dba_audit_session
WHERE 
USERNAME IN ('WAY4U_DATA','OWS_N','WAY4U_BPM')
AND extended_TIMESTAMP between to_date('22.05.2015 12:32','dd.mm.yyyy hh24:mi') and to_date('22.05.2015 12:34','dd.mm.yyyy hh24:mi')
order by extended_timestamp;

--Dead sessions (doesn't present in v$session and no LOGOFF time in audit)
select extended_timestamp,a.* from dba_audit_session a 
left join v$session s on s.audsid=a.sessionid 
where s.sid is null --no entry in v$session
and a.logoff_time is null --no graceful logoff
and a.extended_TIMESTAMP>SYSDATE-2/24 --For last 2 hours
and a.returncode=0 --Login was succesfull
and a.username not in ('ORAMOD','DBSNMP','DBSPI','SPOT') --Exclude monitoring users
order by a.timestamp desc;

--Count of failed login attempts by DB user
select count(*), userhost,username
from dba_audit_session
WHERE RETURNCODE<>0
AND extended_TIMESTAMP > SYSDATE-5/24
--and extended_timestamp < SYSDATE-4/24
group by userhost,username
order by userhost,username;

select * from dba_audit_session where username='GS1' order by timestamp desc;

select * from dba_audit_object where obj_name='OWS_N' order by timestamp desc;

select * from sys.aud$ order by ntimestamp# desc;
select * from dba_audit_trail order by extended_timestamp desc;
select * from dba_users where username='GS1';
select * from dba_profiles where profile='OWS_N_PROFILE';


select * from gv$listener_network;

select to_char(first_time,'YYYY.MM.DD') day,to_char(first_time,'HH24') hour,
count(*) total
from v$log_history
group by to_char(first_time,'YYYY.MM.DD'),to_char(first_time,'HH24')
order by to_char(first_time,'YYYY.MM.DD') desc,to_char(first_time,'HH24') desc;


select * from dba_tablespaces;

select * from dba_tables t,dba_tablespaces ts
where ts.tablespace_name=t.tablespace_name and t.table_name='AUD$';

select count(*),trunc(timestamp,'HH24') hh from dba_audit_trail where timestamp between sysdate-3/24 and sysdate and action_name='LOGON'
group by trunc(timestamp,'HH24');

select * from dba_audit_trail;

select * from dict where table_name like '%AUD%';

select freelists from dba_segments where segment_name='AUD$'; 

select * from DBA_OBJ_AUDIT_OPTS;

select * from v$datafile;

select * from v$archive_dest;

select * from gv$archived_log where dest_id=1 order by first_time desc;

archive log list;

select * from v$archive_processes;

select * from gv$log;

show parameter audit;

select * from dba_profiles where RESOURCE_NAME='PASSWORD_LIFE_TIME';