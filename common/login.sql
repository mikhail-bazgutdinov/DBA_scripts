--MB: commendted out serveroutput to make display_cursor(null,null..) work for the latest SQL executed
--set serveroutput on size 999999 format wrapped
set termout off
set lines           150 
set pages           1000
set long          100000
set longchunksize 100000
set tab              off
set sqlblanklines     on
set exitcommit       off
--Increase arraysize from default 15 to 1000, otherwise 'consistent gets' statistics is much greater 
--when selecting many rows from tables with small row size.
--and it's not just wrong statistics, they are real extra gets from the buffer cache
--statistics to estimate the effectiveness of arraysize is 'SQL*Net roundtrips to/from client'
set arraysize 1000
set feedback off

alter session set nls_date_format      = 'dd.mm.yyyy hh24:mi:ss';
alter session set nls_language         = 'english';
alter session set nls_length_semantics =  char;

--  SQL Prompt {
set termout off
define sqlprompt=none
column sqlprompt new_value sqlprompt

select
   lower(sys_context('USERENV','CURRENT_USER')) || '@' ||
   sys_context('USERENV','DB_NAME'     )
  -- sys_context('USERENV','SERVICE_NAME')
as
   sqlprompt
from
   dual;

set sqlprompt '&sqlprompt> '
undefine sqlprompt
set termout on
-- }
set feedback on


col SQL_HANDLE for a20
col PLAN_NAME for a40
col ORIGIN for a30
col SQL_TEXT for a100
col SIGNATURE for 99999999999999999999
col "Script" for a120
col column_name for a20
col ENDPOINT_ACTUAL_VALUE for a30
col OBJECT_STATUS for a20
col DEPT_NAME for a20
col FIRST_NAME for a30
col LAST_NAME for a30
col EMP_FN for a30
col EMP_LN for a30
col COUNTRY_NAME for a30
col COUNTRY_SUBREGION for a30
col CUST_LAST_NAME for a20
col CUST_FIRST_NAME for a20
col CUST_INCOME_LEVEL for a20
col CUST_STATE_PROVINCE for a20
COL TABLE_NAME FORMAT A30
COL LOCATION FORMAT A18
COL DIRECTORY_NAME FORMAT A40
column NAME FORMAT A40
column USERNAME FORMAT A40
column VALUE Format A40
col network_name format a20
set tab off
set termout on
