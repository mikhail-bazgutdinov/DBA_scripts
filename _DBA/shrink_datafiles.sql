--Finding how much datafiles can be resized: 

COLUMN INSTANCE_NAME NEW_VALUE v_inst noprint
COLUMN HOST_NAME NEW_VALUE v_host noprint
COLUMN THEDATE NEW_VALUE v_date noprint
SELECT instance_name, host_name, TO_CHAR(sysdate,'YYYY-MM-DD') THEDATE
  FROM v$instance;
spool /tmp/shrink_datafiles_&v_inst._&v_host._&v_date..sql

set linesize 120 pagesize 0 heading off
column script format a100
column script2 format a100
spool 
WITH t1 as
  ( 
        SELECT FILE_NAME "File",
            DF.file_id,
            CEIL( (NVL(HWM,1)*tbs.block_size)/1024/1024 ) "Minimum size, Mb",
            CEIL( BLOCKS*tbs.block_size/1024/1024) "Current size, Mb",
            CEIL( BLOCKS*tbs.block_size/1024/1024) - CEIL( (NVL(HWM,1)*tbs.block_size)/1024/1024 ) "Saving, Mb",
            case when CEIL( BLOCKS*tbs.block_size/1024/1024) - CEIL( (NVL(HWM,1)*tbs.block_size)/1024/1024 )>2 then
            'Alter database datafile ''' || FILE_NAME || ''' RESIZE ' || TO_CHAR(CEIL( (NVL(HWM,1)*tbs.block_size)/1024/1024 )+1) ||'M;'
            end "Script",
            case when DF.AUTOEXTENSIBLE='NO' AND CEIL( BLOCKS*tbs.block_size/1024/1024) - CEIL( (NVL(HWM,1)*tbs.block_size)/1024/1024 )>2 then
                'Alter database datafile ''' || FILE_NAME || ''' AUTOEXTEND ON NEXT 10M MAXSIZE ' || CEIL( BLOCKS*tbs.block_size/1024/1024) ||'M;'
            end "Script2"
            FROM DBA_DATA_FILES DF,
            ( SELECT FILE_ID, MAX(BLOCK_ID+BLOCKS-1) HWM FROM DBA_EXTENTS GROUP BY FILE_ID ) HWM,
            dba_tablespaces tbs
            WHERE DF.FILE_ID = HWM.FILE_ID(+)
            and tbs.tablespace_name=df.tablespace_name
            and df.FILE_NAME not like '/lfs%'
            ORDER BY "Saving, Mb" desc
      ) -- end of t1 subquery
SELECT
  t1."Script",
  t1."Script2"
FROM 
   t1
WHERE "Saving, Mb">200;

spool off
spool /tmp/shrink_datafiles_&v_inst._&v_host._&v_date..log
@/tmp/shrink_datafiles_&v_inst._&v_host._&v_date..sql
spool off
exit
