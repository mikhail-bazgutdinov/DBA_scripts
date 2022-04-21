-- Metric v.1
select a.cnt Sample_count, nvl2(o.object_type, o.object_type || ': ' || o.owner || '.' || o.object_name  || NVL2(o.subobject_name,' (' || o.subobject_name || ')',''),'Unknown') ||
  nvl2(ind.table_owner, ' on the ' || ind.table_owner ||'.'||ind.table_name || ' table','') || ' (object_id: ' || a.current_obj# || ')' Index_name
  from (select current_obj#
             , count(*) cnt
          from v$active_session_history
         where sample_time > sysdate-1/24/60*5 ----!!!! last 5 minutes 
           and event = 'enq: TX - index contention'
         group by current_obj#
       ) a
     , dba_objects o
     , dba_indexes ind
where o.object_id (+) = a.current_obj#
and ind.owner(+)=o.owner
and ind.index_name(+)=o.object_name
order by a.cnt desc;

-- Metric v.2 - this metric should only react to high peaks, ignoring small number of different sessions if each of them waited for short time.
--It also considers long waits. If single session waiting more than 5 seconds was found, the monitored metric is multiplied by 10
-- Count of 'enq: TX-index contention' samples in last 5 min of ASH - Average %avg_session_waited% sessions were waited on 'enq: TX - index contention' waitevent in ASH for [%keyValue%] for last 5 minutes. Average wait time was %avg_time_waited_sec% sec. Threshold = 200 sessions (or 20 sessions if waittime were > 5 sec).
-- Average time waited (sec) - Average time waited for 'enq: TX - index contention' waitevent  on %keyValue% for last 5 minutes was %value% sec. About %avg_session_waited% sessions were waited. Threshold = 2 sec.
-- Maximum time waited (sec) - Longest time waited for 'enq: TX - index contention' waitevent  on %keyValue% for last 5 minutes was %value% sec. Threshold = 10 sec. Not reported if it's less than twice greater that average wait time
select * from 
(
select 
    Round(a.Peak_or_long_wait_time) Sample_count,
    nvl2(o.object_type, o.object_type || ': ' || o.owner || '.' || o.object_name  || NVL2(o.subobject_name,' (' || o.subobject_name || ')',''),'Unknown') ||
    nvl2(ind.table_owner, ' on the ' || ind.table_owner ||'.'||ind.table_name || ' table','') || ' (object_id: ' || a.current_obj# || ')' Index_name, 
    Round(a.avg_time_waited/1000000,1) avg_time_waited_sec,
    case when a.avg_time_waited*2<a.max_time_waited then Round(a.max_time_waited/1000000,1) end max_time_waited_sec, 
    Round(avg_samples) avg_session_waited
from (select current_obj#,
          avg(cnt_samples) avg_samples,
          count(distinct sample_time) distinct_sample_time,
          max (avg_not_zero_time_waited) max_time_waited,
          avg (avg_not_zero_time_waited) avg_time_waited,
          case when max (avg_not_zero_time_waited)>5000000 then avg(cnt_samples)*10 else avg(cnt_samples) end Peak_or_long_wait_time
          from
        (select      decode(a2.current_obj#,-1,a1.current_obj#,null,a1.current_obj#,a2.current_obj#) current_obj# 
             , a1.sample_time
             , count(*) cnt_samples
             , count(decode(a1.time_waited,0,null,a1.time_waited)) cnt_not_zero_time_waited
             , avg(decode(a1.time_waited,0,null,a1.time_waited)) avg_not_zero_time_waited
          from v$active_session_history a1
          left join v$active_session_history a2 on a1.blocking_session=a2.session_id and a1.blocking_session_serial#=a2.session_serial# and decode(a1.time_waited,0,a1.sample_id-1,a1.sample_id)=a2.sample_id
         where a1.sample_time > sysdate-1/24/60*5 ----!!!! last 5 minutes
          and a1.event = 'enq: TX - index contention'
         group by decode(a2.current_obj#,-1,a1.current_obj#,null,a1.current_obj#,a2.current_obj#),a1.sample_time
         )
         group by current_obj#
       ) a
     , dba_objects o
     , dba_indexes ind
where o.object_id (+) = a.current_obj#
and ind.owner(+)=o.owner
and ind.index_name(+)=o.object_name
and (a.Peak_or_long_wait_time>10 or a.avg_time_waited/1000000>0.5 or a.max_time_waited/1000000>1) --filtering out too small values to save space in OEM repository
and (ind.index_name != 'GL_TRANSFER_TMP1' or ind.index_name is NULL) -- Leonid Markov does not want alert on this index name
order by a.Peak_or_long_wait_time desc
) where rownum<=3; -- restrict only to 3 top segments on each metric run to prevent incidents storm

