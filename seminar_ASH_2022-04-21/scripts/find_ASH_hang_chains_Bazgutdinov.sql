 with waiters as 
(
	select blocking_Session,blocking_session_Serial#,sample_id,count(*) cnt
	from gv$active_session_history 
	where blocking_session is not null 
	and event in ('library cache lock','cursor: pin S wait on X')
	group by inst_id,blocking_Session,blocking_session_Serial#,sample_id
)
select /*+ NO_MERGE(waiters) */ waiters.cnt "blocked sessions cnt",  ash.* 
from gv$active_session_history ash join waiters on ash.session_id = waiters.blocking_Session 
	and ash.session_serial#=waiters.blocking_session_Serial# and ash.sample_id=waiters.sample_id
order by waiters.cnt desc,sample_time;
