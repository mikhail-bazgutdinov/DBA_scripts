CREATE OR REPLACE TRIGGER logon_denied_write_alertlog AFTER SERVERERROR ON DATABASE
DECLARE
l_message varchar2(4000);
v_module varchar2(50);
v_action varchar2(50);
BEGIN
-- ORA-1017: invalid username/password; logon denied
IF (IS_SERVERERROR(1017)) THEN
dbms_application_info.READ_MODULE(v_module,v_action);

select 'Failed login attempt to the "'|| sys_context('USERENV' ,'AUTHENTICATED_IDENTITY') ||'" schema'
|| ' using ' || sys_context ('USERENV', 'AUTHENTICATION_TYPE') ||' authentication'
|| ' at ' || to_char(logon_time,'dd-MON-yy hh24:mi:ss' )
|| ' machine: ' || osuser ||'@'||machine ||' ['||nvl(sys_context ('USERENV', 'IP_ADDRESS'),'Unknown IP')||']'
|| ' program: "' ||program||'" program.'
|| ' network protocol: "' ||sys_context ('USERENV', 'NETWORK_PROTOCOL')||'".'
|| ' BG_JOB_ID: "' ||sys_context ('USERENV', 'BG_JOB_ID')||'".'
|| ' FG_JOB_ID: "' ||sys_context ('USERENV', 'FG_JOB_ID')||'".'
|| ' AUTHENTICATION_TYPE: "' ||sys_context ('USERENV', 'AUTHENTICATION_TYPE')||'".'
|| ' AUTHENTICATION_DATA: "' ||sys_context ('USERENV', 'AUTHENTICATION_DATA')||'".'
|| ' ENTRYID: "' ||sys_context ('USERENV', 'ENTRYID')||'".'
|| ' EXTERNAL_NAME: "' ||sys_context ('USERENV', 'EXTERNAL_NAME')||'".'
|| ' CURRENT_USER: "' ||sys_context ('USERENV', 'CURRENT_USER')||'".'
|| ' SESSION_USER: "' ||sys_context ('USERENV', 'SESSION_USER')||'".'
|| ' CURRENT_SCHEMA: "' ||sys_context ('USERENV', 'CURRENT_SCHEMA')||'".'
|| ' PROXY_USER: "' ||sys_context ('USERENV', 'PROXY_USER')||'".'
|| ' client_identifier: "' ||sys_context ('USERENV', 'client_identifier')||'".'
|| ' module: "' ||v_module||'".'
|| ' action: "' ||v_action||'".'
	into l_message
from sys .v_$session
where sid = to_number(substr(dbms_session.unique_session_id,1 ,4), 'xxxx')
and serial# = to_number(substr(dbms_session.unique_session_id,5 ,4), 'xxxx');

-- write to alert log
sys.dbms_system.ksdwrt( 2,l_message );
END IF;
END;
/