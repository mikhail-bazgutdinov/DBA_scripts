
   REM Copyright (c) 2000-2012, Oracle Corporation. All rights reserved.
   REM
   REM Use of this script requires purchase of the Oracle Database Diagnostics Pack License.
   
   REM set echo on
   set serveroutput on
   set pages 512
   spool find_ASH_hang_chains.log
   col sql_text for a20
   var dt_format VARCHAR2(25)

   DEF dt_format = 'DD-MON-RR HH24:MI:SS';

   PRO
   PRO Starting_Date_Time (in format '&&dt_format.')
   PRO 
   DEF begin_dt = '&1';
   PRO
   PRO Ending_Date_Time (in format '&&dt_format.')
   PRO
   DEF end_dt = '&2';

   ALTER SESSION SET nls_timestamp_format='&&dt_format.';
 
   DECLARE

   first_time BOOLEAN;

   BEGIN

   FOR sample IN ( SELECT sample_time FROM dba_hist_active_sess_history WHERE sample_time 
   BETWEEN to_timestamp('&&begin_dt.','&&dt_format.') AND
   to_timestamp('&&end_dt.','&&dt_format.') ORDER BY 1 )

   LOOP
   BEGIN

   first_time := TRUE;

   FOR hier IN (

   WITH I AS
   (SELECT /*+ MATERIALIZE */ H.sample_id FROM dba_hist_active_sess_history H
   WHERE H.sample_time=sample.sample_time
   AND H.blocking_hangchain_info='Y')
   SELECT LEVEL, A.session_id, A.session_serial#, A.seq# WAIT_SEQ,
   DECODE(connect_by_iscycle,1,'YES','NO') IS_IN_CYCLE, NVL(A.event,'Not in wait.') WAIT_EVENT, 
   A.time_waited, A.session_type, A.sql_id, SUBSTR(S.sql_text,1,20) SQL_TEXT
   FROM dba_hist_active_sess_history A LEFT OUTER JOIN dba_hist_sqltext S
   ON (A.sql_id=S.sql_id) AND (A.dbid=S.dbid)
   WHERE A.sample_id IN (SELECT sample_id FROM I)
   CONNECT BY NOCYCLE (PRIOR A.session_id=A.blocking_session) AND (PRIOR A.session_serial#=A.blocking_session_serial#) AND
   (PRIOR A.dbid=A.dbid) AND (PRIOR A.instance_number=A.blocking_inst_id) AND (PRIOR A.sample_time=A.sample_time)
   )

   LOOP
   BEGIN

   IF first_time THEN
   BEGIN

   dbms_output.put_line('Time: ' || sample.sample_time);
   dbms_output.put(CHR(10));
   dbms_output.new_line;
   first_time := FALSE;

   END;
   END IF;

   dbms_output.put_line(RPAD('*',hier.LEVEL-1,'*') || 'Sess Id: ' || hier.session_id || ' Ser#: ' || hier.session_serial# ||
   ' Wait Seq: ' || hier.wait_seq || ' In Cycle: ' || hier.is_in_cycle || ' Wait Event: ' || hier.wait_event || ' Time in Wait: ' || hier.time_waited ||
   ' Sess Type: ' || hier.session_type || ' SQL Id: ' || hier.sql_id || ' SQL: ' || hier.sql_text); 

   END;
   END LOOP;
   IF NOT first_time THEN
   BEGIN
   dbms_output.put(CHR(10));
   dbms_output.new_line;
   END;
   END IF;
   END;
   END LOOP;
   END;
   /

   spool off
