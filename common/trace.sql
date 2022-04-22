set echo on
col VALUE for a70
select VALUE from v$diag_info where name='Default Trace File';

