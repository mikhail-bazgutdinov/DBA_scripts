------
----- Collecting database REDO and ARCH summary for list of databases in ACS_DB_INSTANCE table
----- 
set serveroutput on
DECLARE

--List of databases
CURSOR DBNAME_CUR 
  is 
Select distinct ID, instance_name, database_name,dblink_name,version
from ACS_DB_INSTANCE db
WHERE 
--excluded all except databases
INSTANCE_TYPE in ('single','rac') 
--exclude deleted databases
AND DEL_DATE is null
--exclude already collected today
--AND NOT EXISTS (SELECT 1 from ACS_DB_PARAM_HIST dbp where dbp.INST_ID=db.id and dbp.PARAM_NAME='type of parameter file' AND dbp.DATE_COLLECTED=TRUNC(SYSDATE) and dbp.value_char is not null and dbp.value_char not like '%ORA%');
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
        DELETE FROM ACS_DB_ARCLOG_AMOUNT WHERE INST_ID=DBNAME_rec.ID and TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE);
        DELETE FROM ACS_DB_REDO_LOGS WHERE INST_ID=DBNAME_rec.ID and TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE);
        DELETE FROM ACS_DB_REDO_SWITCHES WHERE INST_ID=DBNAME_rec.ID and TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE);
        DELETE FROM ACS_DB_PARAM_HIST  WHERE INST_ID=DBNAME_rec.ID and TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE) and PARAM_NAME='error while collecting redo info';
        DELETE FROM ACS_DB_REDO_LOG_FILE  WHERE INST_ID=DBNAME_rec.ID and TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE);
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

         
        -- Retrieve everything we need
        execute immediate 'INSERT INTO ACS_DB_REDO_LOGS 
          select
          ' || DBNAME_rec.ID || ' inst_id, trunc(sysdate) date_collected,
          (
          select count(*) from v$log@' || v_link_name ||' l join v$instance@' || v_link_name ||'  i on i.thread#=l.thread# where l.members=1 
          ) "Non-mirrored redo logs count",
          --Number of redo-logs where count of redo-member is >1 (mirrored redo logs)
          (select count(*) from v$log@' || v_link_name ||' l join v$instance@' || v_link_name ||'  i on i.thread#=l.thread# where members>1) "Mirrored redo logs count",
          --Size if each redo log
          (select Round(AVG(bytes/1024/1024/1024),2) Gb from v$log@' || v_link_name ||' l join v$instance@' || v_link_name ||'  i on i.thread#=l.thread# ) "Size of redo log, Gb",
          --Number of distinct online redo log sizes (target is 1)
          (select count(distinct bytes) from v$log@' || v_link_name ||' l join v$instance@' || v_link_name ||'  i on i.thread#=l.thread#) "Different redo log sizes"
          from dual';
          
    -- collect logfiles information (note: Oracle 10 does not have "Next_time" column in the v$log view)
		 execute immediate 'INSERT INTO ACS_DB_REDO_LOG_FILE
				select 
        ' || DBNAME_rec.ID || ' inst_id, trunc(sysdate) date_collected,
				l.group# log_group#,
				l.thread# log_thread#,
				l.members log_members
				,l.bytes log_bytes
				,l.archived log_archived
				,l.status log_status
				,l.first_time log_first_time ' ||
				case when SUBSTR(DBNAME_rec.version,1,2)='10' then ',null ' else ',l.next_time log_next_time ' end 
				|| ',f.TYPE logfile_type
				,f.member logfile_member
				,reverse(substr(reverse(f.member),nvl(instr(reverse(f.member),''/''),0)+1,500)) logfile_path
				,f.IS_RECOVERY_DEST_FILE logfile_IS_RECOVERY_DEST_FILE
				from v$log@' || v_link_name ||' l join v$logfile@' || v_link_name ||' f on f.GROUP#=l.group# join v$instance@' || v_link_name ||' i on i.thread#=l.thread#
				order by l.group#';

          execute immediate 'INSERT INTO ACS_DB_REDO_SWITCHES 
          with 
          per_day as 
          (
            select count(distinct thread#) "count of threads", Round(avg("Switch count per day"),1) "Average log switches per day", max("Switch count per day") "Max log switches per day",Round(stddev("Switch count per day"),1) "Stddev log switches per day", 
            Round(avg("Switch count per day")+3*stddev("Switch count per day"),1) "3 sigma for switches per day" from 
            (
            select lh.thread#,trunc(first_time), round(count(*)) "Switch count per day" from v$loghist@' || v_link_name ||' lh join v$instance@' || v_link_name ||' i on i.thread#=lh.thread# 
            where first_time>sysdate-7
            group by trunc(first_time),lh.thread#
            )
          ),
          per_hour as --Redo log switches count per hour for last 7 days
          (
            select Round(avg("Switch count per hour"),1) "Average log switches per hour", max("Switch count per hour") "Max log switches per hour",Round(stddev("Switch count per hour"),1) "Stddev log switches per hour", 
            Round(avg("Switch count per hour")+3*stddev("Switch count per hour"),1) "3 sigma for switches per hour" from 
            (
            select lh.thread#,trunc(first_time,''hh24''), round(count(*)) "Switch count per hour" from v$loghist@' || v_link_name ||' lh join v$instance@' || v_link_name ||' i on i.thread#=lh.thread# 
            where first_time>sysdate-7
            group by trunc(first_time,''hh24''),lh.thread#
            )
          )
          select ' || DBNAME_rec.ID || ' inst_id, trunc(sysdate) date_collected, per_day.*,per_hour.*
          from per_day,per_hour';

          execute immediate 'INSERT INTO ACS_DB_ARCLOG_AMOUNT 
          with per_day as 
          (
          select destination,Round(AVG("Gb per day"),1) "Gb per day,average",Round(Max("Gb per day"),1) "Gb per day, peak",Round(stddev("Gb per day"),1) "Std deviation, Gb per day" from
          (
          select trunc(al.first_time) "Date", destination, sum(blocks*block_size)/1024/1024/1024 "Gb per day" from v$archived_log@' || v_link_name ||' al join v$archive_dest@' || v_link_name ||' ad on ad.dest_id=al.dest_id  join v$instance@' || v_link_name ||'  i on al.thread#=i.thread#
          where al.first_time >sysdate-7
          and ad.schedule=''ACTIVE''  and (ad.destination like ''/%'' or ad.destination like ''USE_DB_RECOVERY_FILE_DEST'')
          group by trunc(al.first_time), destination
          ) group by destination
          ),
          per_hour as
          (
          select destination,Round(AVG("Gb per day"),1) "Gb per hour, average",Round(Max("Gb per day"),1) "Gb per hour, peak",Round(stddev("Gb per day"),1) "Std deviation, Gb per hour" from
          (
          select trunc(al.first_time,''HH24'') "Date", destination, sum(blocks*block_size)/1024/1024/1024 "Gb per day" from v$archived_log@' || v_link_name ||' al join v$archive_dest@' || v_link_name ||' ad on ad.dest_id=al.dest_id   join v$instance@' || v_link_name ||'  i on al.thread#=i.thread#
          where al.first_time >sysdate-7
          and ad.schedule=''ACTIVE'' and (ad.destination like ''/%'' or ad.destination like ''USE_DB_RECOVERY_FILE_DEST'')
          group by trunc(al.first_time,''HH24''), destination
          ) group by destination
          )
          select ' || DBNAME_rec.ID || ' inst_id, trunc(sysdate) date_collected, per_day.*, per_hour."Gb per hour, average","Gb per hour, peak","Std deviation, Gb per hour"
          from per_day join per_hour on per_day.destination=per_hour.destination';
        COMMIT;
     EXCEPTION 
       when OTHERS then 
       v_error_msg := SQLERRM;
       -- log error to value field
		   dbms_output.put_line ( v_link_name || ' - ' || v_error_msg);
       INSERT INTO ACS_DB_PARAM_HIST (INST_ID, PARAM_VALUE, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_error_msg , 'error while collecting redo info',TRUNC(SYSDATE));
       commit;
     end;          
END LOOP;
CLOSE DBNAME_CUR; 
end;
/

       
--errors when collecting redo information
select lower(db.database_name) dbname, instance_name, db.host_name, nvl(par.param_value,'Not collected') "Error", dblink_name
from ACS_DB_PARAM_HIST par join ACS_DB_INSTANCE db on par.INST_ID=db.ID
and (PAR.PARAM_NAME='error while collecting redo info' or PAR.PARAM_NAME is null)
AND (TRUNC(par.DATE_COLLECTED)=TRUNC(SYSDATE) or TRUNC(par.DATE_COLLECTED) is null)
WHERE db.INSTANCE_TYPE in ('single','rac')
order by LOWER(DB.DATABASE_NAME);

-- report for overall online redo log configuration
select 
  l.DATE_COLLECTED,
  --db.critical_group, 
  lower(db.database_name) dbname, 
  db.instance_name, 
  db.host_name, 
  l."Different redo log sizes" , 
  l."Mirrored redo logs count" , 
  l."Non-mirrored redo logs count" , 
  l."Size of redo log, Gb" "Avg size of redo log, Gb"
from ACS_DB_INSTANCE db left join ACS_DB_REDO_LOGS l on l.INST_ID=db.ID
where 
--TRUNC(l.DATE_COLLECTED)=(select max(trunc(date_collected)) from ACS_DB_REDO_LOGS)
--and 
db.host_name='toro.cgs.sbrf.ru' 
and db.del_date is null
order by --db.critical_group desc, 
db.host_name, db.instance_name,date_collected desc;

-- report for redo log switches stats
select 
  s.DATE_COLLECTED,
  db.critical_group, 
  lower(db.database_name) dbname, 
  db.instance_name, 
  db.host_name, 
  s."count of threads" , 
  s."Average log switches per day" , 
  s."Average log switches per hour" , 
  s."Max log switches per day" , 
  s."Max log switches per hour" , 
  s."Stddev log switches per day" , 
  s."Stddev log switches per hour",
  s."3 sigma for switches per day" , 
  s."3 sigma for switches per hour" 
from ACS_DB_INSTANCE db left join ACS_DB_REDO_SWITCHES s on s.INST_ID=db.ID
where 
--TRUNC(s.DATE_COLLECTED)=(select max(trunc(date_collected)) from ACS_DB_REDO_SWITCHES)
db.host_name='toro.cgs.sbrf.ru'
and db.del_date is null
order by db.critical_group desc, db.host_name, db.instance_name,s.date_collected desc;

-- report for redo log files issues
with fs as
(
  SELECT /*+MATERIALIZE*/ 
    host_name,  
    FS_PATH,
    FS_SIZE_MB,
    LAST_COLLECTION
  FROM
  (
  SELECT  decode(target_name,
					'dubna3.cgs.sbrf.ru','way4.cgs.sbrf.ru',
					'dubna4.cgs.sbrf.ru','way4.cgs.sbrf.ru',
					'dubna5.cgs.sbrf.ru','way4.cgs.sbrf.ru',
					'dubna6.cgs.sbrf.ru','way4.cgs.sbrf.ru',
					'klyazma1.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
					'klyazma2.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
					'klyazma3.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
					'klyazma4.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
					'klyazma5.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
					'klyazma6.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
					target_name) host_name, 
         key_value FS_PATH,
         value FS_SIZE_MB,
         collection_timestamp,
         max(collection_timestamp) over (partition by decode(target_name,
																'dubna3.cgs.sbrf.ru','way4.cgs.sbrf.ru',
																'dubna4.cgs.sbrf.ru','way4.cgs.sbrf.ru',
																'dubna5.cgs.sbrf.ru','way4.cgs.sbrf.ru',
																'dubna6.cgs.sbrf.ru','way4.cgs.sbrf.ru',
																'klyazma1.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
																'klyazma2.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
																'klyazma3.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
																'klyazma4.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
																'klyazma5.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
																'klyazma6.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
																target_name) 
													,key_value) LAST_COLLECTION
  FROM MGMT$METRIC_CURRENT@XMONC_EMREP12C
  where  
  METRIC_NAME ='Filesystems' -- this "extra" WHERE condition is to improve query performance
--  and (key_value like '%arclog%' or key_value like '%yastlogs%' or key_value like '/oradata%')
  AND COLUMN_LABEL ='Filesystem Size (MB)'
  )
  WHERE collection_timestamp=LAST_COLLECTION --only last collection
  order by host_name
),
lf as (
select 
  f.DATE_COLLECTED,
  db.critical_group, 
  db.host_name, 
  lower(db.database_name) "Database", 
  db.instance_name "Instance", 
  f.log_group#, 
  f.log_thread#, 
  f.log_members, 
  Round(f.log_bytes/1024/1024,1) "Log size, Mb", 
  --f.log_archived, 
  --f.log_status, 
  --f.log_first_time,
  --f.log_next_time, 
  --f.logfile_type,
  f.logfile_member "Log file",
  f.logfile_path "Path",
  --f.logfile_IS_RECOVERY_DEST_FILE,
    --Complicated condition to find the corresponding filesystem (to deal the difference with /exarclog01 and /exarclogs mounted on the same host)
  (Select FS_PATH from fs where fs.host_name=db.host_name AND (f.logfile_path=fs.FS_PATH OR (instr(f.logfile_path,fs.FS_PATH)>0 AND substr(f.logfile_path,instr(f.logfile_path,fs.FS_PATH)+length(fs.FS_PATH),1)='/')) and rownum=1) "Filesystem",
  (Select Round(FS_SIZE_MB/1024) from fs where fs.host_name=db.host_name AND (f.logfile_path=fs.FS_PATH OR (instr(f.logfile_path,fs.FS_PATH)>0 AND substr(f.logfile_path,instr(f.logfile_path,fs.FS_PATH)+length(fs.FS_PATH),1)='/')) and rownum=1) "Filesystem size, Gb"
from ACS_DB_INSTANCE db left join ACS_DB_REDO_LOG_FILE f on f.INST_ID=db.ID
where TRUNC(f.DATE_COLLECTED)=(select max(trunc(date_collected)) from ACS_DB_REDO_LOG_FILE)
and db.del_date is null
)
select lf.*,
  case when log_members=1 then 'Не зеркалированный online-redo лог. ' end ||
  case when log_members>3 then 'Более 3 копий redo-лога может снизить производительность. ' end ||
  case when "Filesystem" is not null and log_members<>(select count (distinct "Filesystem") from lf lf1 where lf1.host_name=lf.host_name and lf1."Instance"=lf."Instance" and lf1.log_group#=lf.log_group#) then 'Копии редо-логов нужно разместить на разных файловых системах. ' end ||
  case when 1<(select count (distinct "Log size, Mb") from lf lf1 where lf1.host_name=lf.host_name and lf1."Instance"=lf."Instance") then 'Более одного размера redo-группы. ' end "Findings"
from lf
where lf.host_name='toro.cgs.sbrf.ru'
order by critical_group desc, host_name, "Database","Instance", log_group#,"Log file";

-- report for archived log total size
select  TRUNC(a.DATE_COLLECTED) DATE_COLLECTED,
  --db.critical_group, 
  lower(db.database_name) dbname, 
  db.instance_name, 
  db.host_name,
  (select rtrim(XMLAGG(XMLELEMENT(c,t2.DESTINATION|| ',')).EXTRACT('//text()'),',') from acs_db_arclog_amount t2 where t2.INST_ID=a.INST_ID and t2.DATE_COLLECTED=a.DATE_COLLECTED) "Destinations",
  AVG(a."Gb per day,average") "Gb per day,average", 
  AVG(a."Gb per hour, average") "Gb per hour, average", 
  AVG(a."Gb per day, peak") "Gb per day, peak", 
  AVG(a."Gb per hour, peak") "Gb per hour, peak" , 
  AVG(a."Std deviation, Gb per day") "Std deviation, Gb per day"  , 
  AVG(a."Std deviation, Gb per hour") "Std deviation, Gb per hour"
from ACS_DB_INSTANCE db left join acs_db_arclog_amount a on a.INST_ID=db.ID
where TRUNC(a.DATE_COLLECTED)=(select max(trunc(date_collected)) from acs_db_arclog_amount)
and db.del_date is null
--and db.host_name='toro.cgs.sbrf.ru'
group by TRUNC(a.DATE_COLLECTED),
  --db.critical_group, 
  lower(db.database_name), 
  db.instance_name, 
  db.host_name, 
  a.INST_ID,
  a.DATE_COLLECTED
order by TRUNC(a.DATE_COLLECTED) desc ,
--db.critical_group desc, 
db.host_name, db.instance_name;

------------------------------------------------------------------------------------------------------------------------------------------
--Summary report
-- report for overall redo log configuration
with logs as (
select /*+MATERIALIZE*/
  db.id, 
  db.critical_group, 
  lower(db.database_name) dbname, 
  db.instance_name, 
  db.host_name, 
  l."Different redo log sizes" , 
  l."Mirrored redo logs count" , 
  l."Non-mirrored redo logs count" , 
  l."Size of redo log, Gb" "Avg size of redo log, Gb"
from ACS_DB_INSTANCE db left join ACS_DB_REDO_LOGS l on l.INST_ID=db.ID
where TRUNC(l.DATE_COLLECTED)=(select max(trunc(date_collected)) from ACS_DB_REDO_LOGS)
and db.del_date is null
),
swt as 
(
select /*+MATERIALIZE*/ db.id,
  db.critical_group, 
  lower(db.database_name) dbname, 
  db.instance_name, 
  db.host_name, 
  s."count of threads" , 
  s."Average log switches per day" , 
  s."Average log switches per hour" , 
  s."Max log switches per day" , 
  s."Max log switches per hour" , 
  s."Stddev log switches per day" , 
  s."Stddev log switches per hour",
  s."3 sigma for switches per day" , 
  s."3 sigma for switches per hour" 
from ACS_DB_INSTANCE db left join ACS_DB_REDO_SWITCHES s on s.INST_ID=db.ID
where TRUNC(s.DATE_COLLECTED)=(select max(trunc(date_collected)) from ACS_DB_REDO_SWITCHES)
and db.del_date is null
),
--Archlogs filesystems
arc_fs as
(
  SELECT /*+MATERIALIZE*/ 
    host_name,  
    FS_PATH,
    FS_SIZE_MB,
    LAST_COLLECTION
  FROM
  (
  SELECT  decode(target_name,
					'dubna3.cgs.sbrf.ru','way4.cgs.sbrf.ru',
					'dubna4.cgs.sbrf.ru','way4.cgs.sbrf.ru',
					'dubna5.cgs.sbrf.ru','way4.cgs.sbrf.ru',
					'dubna6.cgs.sbrf.ru','way4.cgs.sbrf.ru',
					'klyazma1.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
					'klyazma2.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
					'klyazma3.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
					'klyazma4.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
					'klyazma5.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
					'klyazma6.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
					target_name) host_name, 
         key_value FS_PATH,
         value FS_SIZE_MB,
         collection_timestamp,
         max(collection_timestamp) over (partition by decode(target_name,
																'dubna3.cgs.sbrf.ru','way4.cgs.sbrf.ru',
																'dubna4.cgs.sbrf.ru','way4.cgs.sbrf.ru',
																'dubna5.cgs.sbrf.ru','way4.cgs.sbrf.ru',
																'dubna6.cgs.sbrf.ru','way4.cgs.sbrf.ru',
																'klyazma1.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
																'klyazma2.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
																'klyazma3.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
																'klyazma4.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
																'klyazma5.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
																'klyazma6.cgs.sbrf.ru','klyazma.cgs.sbrf.ru',
																target_name) 
													,key_value) LAST_COLLECTION
  FROM MGMT$METRIC_CURRENT@XMONC_EMREP12C
  where  
  METRIC_NAME ='Filesystems' -- this "extra" WHERE condition is to improve query performance
  and (key_value like '%arclog%' or key_value like '%yastlogs%' or key_value like '/oradata%')
  AND COLUMN_LABEL ='Filesystem Size (MB)'
  )
  WHERE collection_timestamp=LAST_COLLECTION --only last collection
  order by host_name
),
arc as 
(
select /*+MATERIALIZE*/
  db.id,
  db.critical_group, 
  lower(db.database_name) dbname, 
  db.instance_name, 
  db.host_name,
--  (select rtrim(XMLAGG(XMLELEMENT(c,t2.DESTINATION|| ',')).EXTRACT('//text()'),',') from acs_db_arclog_amount t2 where t2.INST_ID=a.INST_ID and t2.DATE_COLLECTED=a.DATE_COLLECTED) "Destinations",
  a.DESTINATION "Destinations",
  --Complicated condition to find the corresponding filesystem (to deal the difference with /exarclog01 and /exarclogs mounted on the same host)
  (Select FS_PATH from arc_fs where arc_fs.host_name=db.host_name AND (a.DESTINATION=arc_fs.FS_PATH OR (instr(a.DESTINATION,arc_fs.FS_PATH)>0 AND substr(a.DESTINATION,instr(a.DESTINATION,arc_fs.FS_PATH)+length(arc_fs.FS_PATH),1)='/')) and rownum=1) "Filesystem",
  (Select Round(arc_fs.fs_size_Mb/1024) from arc_fs where arc_fs.host_name=db.host_name AND (a.DESTINATION=arc_fs.FS_PATH OR instr(a.DESTINATION,arc_fs.FS_PATH)>0 AND substr(a.DESTINATION,instr(a.DESTINATION,arc_fs.FS_PATH)+length(arc_fs.FS_PATH),1)='/') and rownum=1) "FS size, Gb",
  a."Gb per day,average" "Gb per day,average", 
  a."Gb per hour, average" "Gb per hour, average", 
  a."Gb per day, peak" "Gb per day, peak", 
  a."Gb per hour, peak" "Gb per hour, peak" , 
  a."Std deviation, Gb per day" "Std deviation, Gb per day"  , 
  a."Std deviation, Gb per hour" "Std deviation, Gb per hour",
  Greatest(a."Gb per day,average"*2,a."Gb per day, peak"*1.25) "Recommended arc FS size,Gb" --author of the formula is Nataly Yakovleva
from ACS_DB_INSTANCE db left join acs_db_arclog_amount a on a.INST_ID=db.ID
where TRUNC(a.DATE_COLLECTED)=(select max(trunc(date_collected)) from acs_db_arclog_amount)
and db.del_date is null
)
select logs.Critical_group "Group", 
    logs.host_name,
    logs.dbname,
    logs.instance_name,
    logs."Different redo log sizes" , 
    logs."Mirrored redo logs count" , 
    logs."Non-mirrored redo logs count" , 
    logs."Avg size of redo log, Gb",
    case when logs."Different redo log sizes">1 then 'Все redo-логи должны быть одного размера. ' end ||
    case when logs."Non-mirrored redo logs count">0 then 'зеркалировать файлы redo-логов. ' end ||
    case when swt."Average log switches per hour">7 OR swt."3 sigma for switches per hour">21 then 
    'Увеличить размер Redo-лога на ' || Round(greatest (swt."Average log switches per hour",swt."3 sigma for switches per hour"/3)/5*100-100) || '% до ' || Round(greatest (swt."Average log switches per hour",swt."3 sigma for switches per hour"/3)/5*logs."Avg size of redo log, Gb"*1024) || ' Mб (цель - переключение 5 раз в час). ' end "Recommendation", -- Target - 5 times per hour
    swt."Average log switches per day" , 
    swt."Average log switches per hour" , 
    swt."Max log switches per day" , 
    swt."Max log switches per hour" , 
    swt."Stddev log switches per day" , 
    swt."Stddev log switches per hour",
    swt."3 sigma for switches per day" , 
    swt."3 sigma for switches per hour",
    arc."Destinations",
    arc."Filesystem",
    arc."FS size, Gb",
    arc."Gb per day,average", 
    arc."Gb per hour, average", 
    arc."Gb per day, peak", 
    arc."Gb per hour, peak" , 
    arc."Std deviation, Gb per day" "Gb per day, Std deviation" , 
    arc."Std deviation, Gb per hour" "Gb per hour, Std deviation",
    Greatest(Round(arc."Recommended arc FS size,Gb"),10) "Recommended arc FS size,Gb", 
    Round(arc."FS size, Gb"*0.8/arc."Gb per hour, peak",1) "suggest arclog del interval, h",
    --0.0001 to avoid "division by zero" error
    Round(arc."FS size, Gb"*0.8/(arc."Gb per hour, average"+arc."Std deviation, Gb per hour"+0.001),1) "suggest arclog del interval, h",
    Round(arc."FS size, Gb" / arc."Recommended arc FS size,Gb",1) "FS size, ratio of recommended",
    case when arc."Destinations" not like '%arclog%' and arc."Destinations" not like 'USE_DB_RECOVERY_FILE_DEST' then
      'Используйте для архивных журналов файловую систему, содержающую слово arclog в пути точки монтирования. '
      when arc."Destinations" not like 'USE_DB_RECOVERY_FILE_DEST' and
      arc."Filesystem" not like '%arclog%' then
      'Используйте для архивных журналов файловую систему, содержающую слово arclog в пути точки монтирования. '
    end ||
    -- If actual FS size less then 95% of recommended FS size, then recommend to increase FS size
    case when arc."FS size, Gb"<Round(arc."Recommended arc FS size,Gb")*0.95 then
      'Увеличить размер FS до ' || Round(Greatest(arc."Gb per day,average"*2,arc."Gb per day, peak"*1.25)) || ' Gb. '
    end ||
    -- If actual FS size greater then 500% of recommended FS size, then recommend to shrink FS size down to least of values: 2*"Recommended FS size" or 10Gb
    case when arc."FS size, Gb">arc."Recommended arc FS size,Gb"*5  AND arc."Filesystem" like '%arclog%'
    then
      'Уменьшить размер FS до ' || Greatest(Round(Greatest(arc."Gb per day,average"*2,arc."Gb per day, peak"*1.25))*2,10) || ' Gb. '
    end
    "Arclog FS recommendation"
from logs left join swt on logs.id=swt.id
left join arc on arc.id=logs.id
order by "Group" desc,HOST_NAME,instance_name;

select TRUNC(par.DATE_COLLECTED), lower(db.database_name) dbname, instance_name, db.host_name, param_name, nvl(par.param_value,'Not collected') "Value"
from ACS_DB_PARAM_HIST par join ACS_DB_INSTANCE db on par.INST_ID=db.ID
WHERE db.host_name='alamo.cgs.sbrf.ru'
--and TRUNC(par.DATE_COLLECTED)=to_date('27.11.2014','dd.mm.yyyy')
and param_name='processes'
order by TRUNC(par.DATE_COLLECTED), LOWER(DB.DATABASE_NAME),param_name;

