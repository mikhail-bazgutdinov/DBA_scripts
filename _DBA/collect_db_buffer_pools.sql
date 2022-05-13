------
----- Collecting database buffer pools summary and usage for list of databases in ACS_DB_INSTANCE table
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
        DELETE FROM acs_db_buffer_pools WHERE INST_ID=DBNAME_rec.ID and TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE);
        DELETE FROM ACS_DB_PARAM_HIST  WHERE INST_ID=DBNAME_rec.ID and TRUNC(DATE_COLLECTED)=TRUNC(SYSDATE) and PARAM_NAME='error while collecting buffer pool info';
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
          execute immediate 'INSERT INTO acs_db_buffer_pools (INST_ID                    ,
                                                              DATE_COLLECTED             ,
                                                              BUFFER_POOL                ,
                                                              BLOCK_SIZE                 ,
                                                              BUFFER_SIZE_MB             ,
                                                              SEGMENT_SIZE_MB_EXCEPT_LOB ,
                                                              SEGMENT_COUNT_EXCEPT_LOB   ,
                                                              LOBS_CACHED_SEG_SIZE_MB    ,
                                                              LOBS_CACHED_SEG_COUNT      ,
                                                              LOBS_NOT_CACHED_SEG_SIZE_MB,
                                                              LOBS_NOT_CACHED_SEG_COUNT,                                                              
                                                              FREE_BUFFER_WAIT           ,
                                                              BUFFER_BUSY_WAIT           ,
                                                              DB_BLOCK_CHANGE            ,
                                                              DB_BLOCK_GETS              ,
                                                              PHYSICAL_READS             ,
                                                              PHYSICAL_WRITES     )
          with seg as 
          (
            select /*+MATERIALIZE*/
            s.buffer_pool,
            t.block_size ,
              Round(sum(decode(l.cache,null,s.bytes))/1024/1024) Segment_size_mb_except_LOB,
              count(decode(l.cache,null,s.bytes)) Segment_count_except_LOB,
              Round(sum(decode(l.cache,''YES'',s.bytes))/1024/1024) LOBs_Cached_Seg_size_mb,
              count(decode(l.cache,''YES'',s.bytes)) LOBs_Cached_Seg_count,
              Round(sum(decode(l.cache,''NO'',s.bytes))/1024/1024) LOBs_Not_Cached_Seg_size_mb,
              count(decode(l.cache,''NO'',s.bytes)) LOBs_Not_Cached_Seg_count
            from 
              dba_segments@' || v_link_name ||' s join dba_tablespaces@' || v_link_name ||' t on s.tablespace_name=t.tablespace_name
              left join dba_lobs@' || v_link_name ||' l on l.segment_name=s.segment_name
            group by s.buffer_pool, t.block_size
          )
                    select ' || DBNAME_rec.ID || ' inst_id, trunc(sysdate) date_collected,   nvl(buf.name,seg.buffer_pool) buffer_pool,
            nvl(buf.block_size,seg.block_size) block_size,
            buf.current_size buffer_size_mb,
            NVL(seg.Segment_size_mb_except_LOB,0),
            NVL(seg.Segment_count_except_LOB,0),
            NVL(seg.LOBs_Cached_Seg_size_mb,0),
            NVL(seg.LOBs_Cached_Seg_count,0),
            NVL(seg.LOBs_Not_Cached_Seg_size_mb,0),
            NVL(seg.LOBs_Not_Cached_Seg_count,0),
            st.free_buffer_wait,
            st.buffer_busy_wait,
            st.db_block_change,
            st.db_block_gets,
            st.physical_reads,
            st.physical_writes
          from v$buffer_pool_statistics@' || v_link_name ||' st join v$buffer_pool@' || v_link_name ||' buf on buf.name=st.name and buf.block_size=st.block_size
          full outer join seg on buf.name=seg.buffer_pool and buf.block_size=seg.block_size';
        COMMIT;
     EXCEPTION 
       when OTHERS then 
       v_error_msg := SQLERRM;
       -- log error to value field
		   dbms_output.put_line ( v_link_name || ' - ' || v_error_msg);
       INSERT INTO ACS_DB_PARAM_HIST (INST_ID, PARAM_VALUE, PARAM_NAME, DATE_COLLECTED) VALUES(DBNAME_rec.ID, v_error_msg , 'error while collecting buffer pool info',TRUNC(SYSDATE));
       commit;
     end;          
END LOOP;
CLOSE DBNAME_CUR; 
end;
/

       
--errors when collecting buffer pool information
select DATE_COLLECTED, lower(db.database_name) dbname, instance_name, db.host_name, nvl(par.param_value,'Not collected') "Error", dblink_name
from ACS_DB_PARAM_HIST par join ACS_DB_INSTANCE db on par.INST_ID=db.ID
and (PAR.PARAM_NAME='error while collecting buffer pool info' or PAR.PARAM_NAME is null)
AND (TRUNC(par.DATE_COLLECTED)=TRUNC(SYSDATE) or TRUNC(par.DATE_COLLECTED) is null)
WHERE db.INSTANCE_TYPE in ('single','rac')
union all
SELECT MAX (DATE_COLLECTED) DATE_COLLECTED, null dbname,null instance_name,  null host_name, 'Last collection marker' "Error", null dblink_name
from acs_db_buffer_pools
order by DATE_COLLECTED desc, dbname nulls first;

------------------------------------------------------------------------------------------------------------------------------------------
--Summary report
-- report for overall buffer pool configuration
with recom as 
(
select 
    db.id,
    db.host_name,
    db.database_name,
    db.instance_name,
    Round(
    to_number(Replace(Replace(Replace(sga_max.param_value,'M',''),'K',''),'G',''))*case when INSTR(sga_max.param_value,'K')>0 then 1024
                                                                                        when INSTR(sga_max.param_value,'M')>0 then 1024*1024
                                                                                        when INSTR(sga_max.param_value,'G')>0 then 1024*1024*1024
    end/1024/1024/1024
        ) sga_max_size_gb,
    db_block.param_value/1024 || 'K' db_block_size,
    buf.buffer_pool,
    to_char(buf.block_size/1024) || 'K' block_size,
    buf.BUFFER_SIZE_MB,
    Round((buf.SEGMENT_SIZE_MB_EXCEPT_LOB+buf.LOBS_CACHED_SEG_SIZE_MB)/1024) "Cached segments size,Gb",
    buf.SEGMENT_COUNT_EXCEPT_LOB + buf.LOBS_CACHED_SEG_COUNT "Cached segments count",
    Round(buf.LOBS_NOT_CACHED_SEG_SIZE_MB/1024) "Not cached segments size,Gb",
    buf.LOBS_NOT_CACHED_SEG_COUNT "Not cached segments count",
    Round(buf.db_block_change/1000000) "Block changes, mln",
    Round(buf.db_block_gets/1000000) "Block gets, mln",
    Round(buf.physical_reads/1000000) "Physical reads, mln",
    --Round(buf.physical_writes) "Physical writes, mln"
    case when buf.SEGMENT_COUNT_EXCEPT_LOB+buf.LOBS_CACHED_SEG_COUNT=0 and buf.BUFFER_SIZE_MB>0 then 'DROP' --We recommend to drop the buffer if there is no segments assigned to it (do not count for Not-cached LOB here)
         when buf.Segment_size_mb_except_LOB+LOBS_CACHED_SEG_SIZE_MB<buf.BUFFER_SIZE_MB*0.9 then 'SHRINK'   --We only recommend to shrink the buffer if total segment size is less than 90% of buffer size and buffer is not default
         when buf.SEGMENT_COUNT_EXCEPT_LOB+LOBS_CACHED_SEG_COUNT > 0 and nvl(buf.BUFFER_SIZE_MB,0)=0 then 'CREATE' end  --We recommend to create the buffer if it is not exist and there is >0 segments assigned to it (do not count for Not-cached LOB here)
    "Recommendation"
from acs_db_buffer_pools buf join ACS_DB_INSTANCE db on buf.INST_ID=db.ID
left join  ACS_DB_PARAM_HIST sga_max on sga_max.PARAM_NAME = 'sga_max_size' and sga_max.INST_ID=db.ID
left join  ACS_DB_PARAM_HIST db_block on db_block.PARAM_NAME = 'db_block_size' and db_block.INST_ID=db.ID
where TRUNC(buf.DATE_COLLECTED) = (select max(trunc(DATE_COLLECTED)) from acs_db_buffer_pools)
and TRUNC(sga_max.DATE_COLLECTED) = (select max(trunc(DATE_COLLECTED)) from ACS_DB_PARAM_HIST where INST_ID=db.ID and PARAM_NAME = 'sga_max_size')
and TRUNC(db_block.DATE_COLLECTED) = (select max(trunc(DATE_COLLECTED)) from ACS_DB_PARAM_HIST where INST_ID=db.ID and PARAM_NAME = 'db_block_size')
)
select 
    case when nvl(lag(r1.host_name,1) over (order by r1.HOST_NAME,r1.instance_name,r1.buffer_pool,r1.block_size),'zz')<>r1.host_name then r1.host_name end "Host name",
    case when nvl(lag(r1.host_name||r1.database_name,1) over (order by r1.HOST_NAME,r1.instance_name,r1.buffer_pool,r1.block_size),'zz')<>r1.host_name||r1.database_name then r1.database_name end "Database name",
    case when r1.instance_name<>r1.database_name then r1.instance_name end "Instance name (for RAC db)", 
    case when nvl(lag(r1.host_name||r1.database_name,1) over (order by r1.HOST_NAME,r1.instance_name,r1.buffer_pool,r1.block_size),'zz')<>r1.host_name||r1.database_name then r1.db_block_size end "DB default block size",
    case when nvl(lag(r1.host_name||r1.database_name,1) over (order by r1.HOST_NAME,r1.instance_name,r1.buffer_pool,r1.block_size),'zz')<>r1.host_name||r1.database_name OR r1.instance_name<>r1.database_name then r1.sga_max_size_gb end "sga_max_size, Gb",
    case when r1.buffer_pool='DEFAULT' and r1.db_block_size=r1.block_size then r1.buffer_pool
         when r1.buffer_pool='DEFAULT' and r1.db_block_size<>r1.block_size then r1.block_size
         else r1.buffer_pool
    end "Buffer pool",
    Round(r1.BUFFER_SIZE_MB/1024,1) "Buffer size,Gb",
    r1."Cached segments size,Gb",
    --r1."Cached segments count",
    r1."Not cached segments size,Gb",
    --r1."Not cached segments count",
    r1."Block changes, mln",
    r1."Block gets, mln",
    r1."Physical reads, mln",
    --r1."Recommendation",
    case when "Recommendation"='DROP' then 'Для буфера нет ни одного сегмента. Под буфер в SGA выделено ' || round(r1.BUFFER_SIZE_MB/1024) || 'Gb из ' || r1.sga_max_size_gb || '.' end ||
    case when "Recommendation"='SHRINK' then 'Суммарный размер кэшируемых сегментов (' || r1."Cached segments size,Gb" || ' Gb) значительно меньше размера буфера (' || to_char(round(r1.BUFFER_SIZE_MB/1024,1)) || 'Gb).' end ||
    case when "Recommendation"='CREATE' then r1.buffer_pool || ' буфер для сегментов размером блока ' || r1.block_size || ' не создан. В базе имеется ' ||  r1."Cached segments count" || ' сегментов, подлежащих кэшированию в ' || r1.buffer_pool || case when r1.db_block_size<>r1.block_size then '('|| r1.block_size || ')' end || '-буфере (т.е. либо не-LOB''ов, либо LOB-ов с параметром CACHE) суммарным размером ' ||  r1."Cached segments size,Gb" || 'Gb' 
    end "Issue",
    case when "Recommendation"='DROP' then 'Удалить буфер ' || case when buffer_pool in ('KEEP','RECYCLE') and r1.db_block_size=r1.block_size then 'db_'||lower(buffer_pool)||'_cache_size'
                                                                           when buffer_pool in ('DEFAULT') and r1.db_block_size<>r1.block_size then 'db_'||lower(r1.block_size)||'_cache_size'
                                                                           when buffer_pool in ('KEEP','RECYCLE') and r1.db_block_size<>r1.block_size then ' Внимание: обнаружен ' ||buffer_pool||' буфер с размером блока, отличного от дефолтного. Таких буферов в Oracle не бывает.'
                                                                           else 'Обратитесь в Oracle Support' 
                                                                   end
    end ||
    case when "Recommendation"='SHRINK' then 'Уменьшить размер буфера "' || case when buffer_pool in ('KEEP','RECYCLE') and r1.db_block_size=r1.block_size then 'db_'||lower(buffer_pool)||'_cache_size'
                                                                           when buffer_pool in ('DEFAULT') and r1.db_block_size<>r1.block_size then 'db_'||lower(r1.block_size)||'_cache_size'
                                                                           when buffer_pool in ('KEEP','RECYCLE') and r1.db_block_size<>r1.block_size then ' Внимание: объекты назначены на ' ||buffer_pool||' буфер с размером блока, отличного от дефолтного. Таких буферов в Oracle не бывает.'
                                                                           when buffer_pool in ('DEFAULT') and r1.db_block_size=r1.block_size then 'db_cache_size'
                                                                           else 'Обратитесь в Oracle Support' 
                                                                                                                  end || '" до ' || r1."Cached segments size,Gb" || 'Gb или менее.' 
    end ||
    case when "Recommendation"='CREATE' then 'Явно указать, что сегменты должны отправиться в DEFAULT-буфер.'  || case when buffer_pool in ('KEEP','RECYCLE') and r1.db_block_size=r1.block_size then ' Или создать буфер db_'||lower(buffer_pool)||'_cache_size'
                                                                                                                       when buffer_pool in ('DEFAULT') and r1.db_block_size<>r1.block_size then ' Или создать буфер db_'||lower(r1.block_size)||'_cache_size'
                                                                                                                       when buffer_pool in ('KEEP','RECYCLE') and r1.db_block_size<>r1.block_size then ' Внимание: объекты назначены на ' ||buffer_pool||' буфер с размером блока, отличного от дефолтного. Таких буферов в Oracle не бывает.'
                                                                                                                       when buffer_pool in ('DEFAULT') and r1.db_block_size=r1.block_size then ' В базе не задан buffer cache по умолчанию?'
                                                                                                                       else 'Обратитесь в Oracle Support' 
    end
    end "Recommendation"
from recom r1
--where exists (select 1 from recom r2 where r1.id=r2.id and r2."Recommendation" is not null) --Show only databases which have recommendations
--where r1.buffer_pool='KEEP'
order by r1.HOST_NAME,r1.instance_name,decode(r1.db_block_size,r1.block_size,0,1), r1.buffer_pool, r1.block_size;

--Compare to previous collection and show only differences
with dt as
(
select
  (select max(buf.DATE_COLLECTED) from acs_db_buffer_pools buf) LAST_COLL,
  (select max(buf.DATE_COLLECTED) from acs_db_buffer_pools buf where buf.DATE_COLLECTED<>(select max(buf.DATE_COLLECTED) from ACS_DB_VERSION_HIST buf)) PREV_COLL
from dual
)
SELECT DB.HOST_NAME, LOWER(DB.DATABASE_NAME) DBNAME,INSTANCE_NAME,
NVL(buf_p.buffer_pool,buf_c.buffer_pool) buffer_pool,
NVL(buf_p.block_size,buf_c.block_size)/1024 || 'K' block_size,
TO_CHAR(buf_c.DATE_COLLECTED,'dd.mm.yyyy') "Latest collection",
TO_CHAR(buf_p.DATE_COLLECTED,'dd.mm.yyyy') "Previous collection",
CASE WHEN NVL(buf_c.BUFFER_SIZE_MB,0)<>NVL(buf_p.BUFFER_SIZE_MB,0) 
  THEN buf_p.BUFFER_SIZE_MB || '-->' || buf_c.BUFFER_SIZE_MB 
  else to_char(buf_c.BUFFER_SIZE_MB)
end "Buffer size (MB), change",
case when '0'<>(select max(param_value) from ACS_DB_PARAM_HIST par where DATE_COLLECTED=(select max(DATE_COLLECTED) from ACS_DB_PARAM_HIST where PARAM_NAME='db_block_size') and par.PARAM_NAME in ('sga_target','memory_target') and par.INST_ID=db.ID) then 'Yes'
end "Dynamic SGA"
from ACS_DB_INSTANCE db join dt on 1=1
  LEFT JOIN acs_db_buffer_pools buf_c on buf_c.INST_ID=db.ID and buf_c.DATE_COLLECTED=dt.last_coll
  LEFT JOIN acs_db_buffer_pools buf_p on buf_p.INST_ID=db.ID and buf_p.DATE_COLLECTED=dt.prev_coll and buf_p.buffer_pool=buf_c.buffer_pool and buf_p.block_size=buf_c.block_size
WHERE 
DB.DEL_DATE is null
AND NVL(buf_c.BUFFER_SIZE_MB,0)<>NVL(buf_p.BUFFER_SIZE_MB,0)
order by buf_p.DATE_COLLECTED desc, DB.HOST_NAME, DB.instance_name;

--Compare buffer sizes for RAC instances
with dt as
(
select
(select max(buf.DATE_COLLECTED) from acs_db_buffer_pools buf) LAST_COLL,
(select max(buf.DATE_COLLECTED) from acs_db_buffer_pools buf where buf.DATE_COLLECTED<>(select max(buf.DATE_COLLECTED) from ACS_DB_VERSION_HIST buf)) PREV_COLL
from dual)
SELECT DB.HOST_NAME, LOWER(DB.DATABASE_NAME) DBNAME,INSTANCE_NAME,
NVL(buf_p.buffer_pool,buf_c.buffer_pool) buffer_pool,
NVL(buf_p.block_size,buf_c.block_size)/1024 || 'K' block_size,
TO_CHAR(buf_c.DATE_COLLECTED,'dd.mm.yyyy') "Latest collection",
TO_CHAR(buf_p.DATE_COLLECTED,'dd.mm.yyyy') "Previous collection",
CASE WHEN NVL(buf_c.BUFFER_SIZE_MB,0)<>NVL(buf_p.BUFFER_SIZE_MB,0) 
  THEN buf_p.BUFFER_SIZE_MB || '-->' || buf_c.BUFFER_SIZE_MB 
  else to_char(buf_c.BUFFER_SIZE_MB)
end "Buffer size (MB), change"
from ACS_DB_INSTANCE db join dt on 1=1
  LEFT JOIN acs_db_buffer_pools buf_c on buf_c.INST_ID=db.ID and buf_c.DATE_COLLECTED=dt.last_coll
  LEFT JOIN acs_db_buffer_pools buf_p on buf_p.INST_ID=db.ID and buf_p.DATE_COLLECTED=dt.prev_coll and buf_p.buffer_pool=buf_c.buffer_pool and buf_p.block_size=buf_c.block_size
WHERE 
DB.DEL_DATE is null
AND db.instance_type like '%rac%'
--AND NVL(buf_c.BUFFER_SIZE_MB,0)<>NVL(buf_p.BUFFER_SIZE_MB,0)
order by buf_p.DATE_COLLECTED desc, substr(DB.HOST_NAME,1,5), db.database_name, buffer_pool, DB.instance_name;

--Example of data gathered from the database
with seg as 
(
  select /*+MATERIALIZE*/
  s.buffer_pool,
  t.block_size ,
    Round(sum(decode(l.cache,null,s.bytes))/1024/1024) Segment_size_mb_except_LOB,
    count(decode(l.cache,null,s.bytes)) Segment_count_except_LOB,
    Round(sum(decode(l.cache,'YES',s.bytes))/1024/1024) LOBs_Cached_Seg_size_mb,
    count(decode(l.cache,'YES',s.bytes)) LOBs_Cached_Seg_count,
    Round(sum(decode(l.cache,'NO',s.bytes))/1024/1024) LOBs_Not_Cached_Seg_size_mb,
    count(decode(l.cache,'NO',s.bytes)) LOBs_Not_Cached_Seg_count
  from 
    dba_segments s join dba_tablespaces t on s.tablespace_name=t.tablespace_name
    left join dba_lobs l on l.segment_name=s.segment_name
  group by s.buffer_pool, t.block_size
)
          select nvl(buf.name,seg.buffer_pool) buffer_pool,
  nvl(buf.block_size,seg.block_size) block_size,
  buf.current_size buffer_size_mb,
  NVL(seg.Segment_size_mb_except_LOB,0) Segment_size_mb_except_LOB,
  NVL(seg.Segment_count_except_LOB,0) Segment_count_except_LOB,
  NVL(seg.LOBs_Cached_Seg_size_mb,0) LOBs_Cached_Seg_size_mb,
  NVL(seg.LOBs_Cached_Seg_count,0) LOBs_Cached_Seg_count,
  NVL(seg.LOBs_Not_Cached_Seg_size_mb,0) LOBs_Not_Cached_Seg_size_mb,
  NVL(seg.LOBs_Not_Cached_Seg_count,0) LOBs_Not_Cached_Seg_count,
  st.free_buffer_wait,
  st.buffer_busy_wait,
  st.db_block_change,
  st.db_block_gets,
  st.physical_reads,
  st.physical_writes
from v$buffer_pool_statistics st join v$buffer_pool buf on buf.name=st.name and buf.block_size=st.block_size
full outer join seg on buf.name=seg.buffer_pool and buf.block_size=seg.block_size;

select * from user_Lobs;
select * from user_role_privs;