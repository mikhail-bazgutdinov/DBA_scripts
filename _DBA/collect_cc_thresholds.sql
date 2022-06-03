set feedback off

prompt "========================================================================================================================"
prompt "========================================================================================================================"
prompt "========================================================================================================================"

select to_char(sysdate,'dd.mm.yyyy hh24:mi') "SYSDATE" from dual;
prompt "========================================================================================================================"
prompt "========================================================================================================================"
PROMPT "========================================================================================================================"
SELECT COLL_INTERVAL, TIME_UNIT FROM 
XMLTABLE('/Schedule' passing XMLType(t.sch) columns coll_interval varchar2(20) path '@INTERVAL', TIME_UNIT Varchar2(20) path '@TIME_UNIT')
, (SELECT '"<Schedule START_DATE="2014-11-02" START_TIME="10:00:00"> 	<IntervalSchedule INTERVAL="24" TIME_UNIT="Hr"/> </Schedule> "' SCH FROM DUAL) T;
DESC SYSMAN.MGMT_METRIC_COLLECTIONS@XMONC_EMREP12C COLLS
SELECT --SCHEDULE_EX
--,NVL2(SCHEDULE_EX,XMLTYPE(TRIM(SCHEDULE_EX)),NULL),
XMLTYPE(TRIM(SCHEDULE_EX)),
CASE WHEN TRIM(COLLS.SCHEDULE_EX) IS NOT NULL THEN 
EXTRACTVALUE(XMLTYPE(COLLS.SCHEDULE_EX),'/Schedule/IntervalSchedule/@INTERVAL') || ' ' || NVL(EXTRACTVALUE(XMLTYPE(COLLS.SCHEDULE_EX),'/Schedule/IntervalSchedule/@TIME_UNIT'),'Min')
end "Schedule"
FROM SYSMAN.MGMT_METRIC_COLLECTIONS@XMONC_EMREP12C COLLS
where Trim(SCHEDULE_EX) is not null;

-- Collect current values of thresholds to the ACS_METRIC_THRESH_HIST table (DONT forget to commit!!!!)
DELETE FROM ACS_METRIC_THRESH_HIST WHERE DATE_COLLECTED=TRUNC(SYSDATE);
delete from ACS_METRIC_THRESH_HIST where DATE_COLLECTED>sYSdate-1/24;
commit;
INSERT INTO ACS_METRIC_THRESH_HIST
SELECT     
    TRUNC(SYSDATE) as DATE_COLLECTED,
    TAR.TARGET_TYPE,
    TAR.TARGET_NAME, 
    (SELECT RTRIM(XMLAGG(XMLELEMENT(C,AGGREGATE_TARGET_NAME|| ',') ORDER BY AGGREGATE_TARGET_NAME).EXTRACT('//text()'),',') FROM MGMT$TARGET_MEMBERS@XMONC_EMREP12C TM WHERE TM.MEMBER_TARGET_GUID=TAR.TARGET_GUID AND AGGREGATE_TARGET_TYPE='composite') GROUPS_GRID,
    TAR.HOST_NAME, 
    CASE WHEN MET.COLUMN_LABEL IN ('User-Defined Numeric Metric','User Defined Numeric Metric') THEN 'UDM: ' || MET.COLLECTION_NAME
         WHEN  MET.METRIC_NAME LIKE 'alertLog%' OR MET.METRIC_NAME LIKE 'db_alert_log%'         THEN met_lbl.METRIC_LABEL||' - ' || MET.COLUMN_LABEL
         WHEN  MET.COLUMN_LABEL IN ('Status'
                                      ,'State'
                                      ,'Out of Memory'
                                      ,'Oracle Data Block Corruption'
                                      ,'Media Failure'
                                      ,'Internal SQL Error'
                                      ,'Interface Type'
                                      ,'Error Count'
                                      ,'Data Failure Detected'
                                      ,'Data Block Corruption'
                                      ,'Cluster Error'
                                      ,'Archiver Hung'
                                      ,'Redo Log Corruption')  OR met_lbl.METRIC_LABEL='Incident'  THEN met_lbl.METRIC_LABEL||' - ' || MET.COLUMN_LABEL
         else MET.COLUMN_LABEL
    end METRIC,
    Trim(DECODE(met.column_label,'User-Defined Numeric Metric',MET.KEY_VALUE2,'User Defined Numeric Metric',MET.KEY_VALUE2,MET.KEY_VALUE)) KEY_VALUE,
         DECODE (critical_operator,
                 0, '>',
                 2, '<',
                 3, '<=',
                 4, '>=',
                 1, '=',
                 5, 'Contains',
                 6, '<>',
                 7, 'Matches',
                 TO_CHAR (MET.WARNING_OPERATOR)
                ) COMPARISON_OPERATOR, 
         Trim(MET.WARNING_THRESHOLD) WARNING_THRESHOLD, 
         TRIM(MET.CRITICAL_THRESHOLD) CRITICAL_THRESHOLD,
         MET.OCCURRENCE_COUNT,
         CASE WHEN TRIM(COLLS.SCHEDULE_EX) IS NOT NULL THEN 
          EXTRACTVALUE(XMLTYPE(COLLS.SCHEDULE_EX),'/Schedule/IntervalSchedule/@INTERVAL') || ' ' || NVL(EXTRACTVALUE(XMLTYPE(COLLS.SCHEDULE_EX),'/Schedule/IntervalSchedule/@TIME_UNIT'),'Min')
          end COLLECTION_FREQUENCY,
         C.IS_ENABLED
    FROM  SYSMAN.MGMT$TARGET@XMONC_EMREP18C TAR 
          LEFT JOIN SYSMAN.MGMT$TARGET_METRIC_SETTINGS@XMONC_EMREP18C MET ON MET.TARGET_GUID=TAR.TARGET_GUID
          LEFT JOIN SYSMAN.MGMT$TARGET_METRIC_COLLECTIONS@XMONC_EMREP18C C ON C.TARGET_GUID=TAR.TARGET_GUID AND C.METRIC_NAME = MET.METRIC_NAME AND C.COLLECTION_NAME = MET.COLLECTION_NAME
          LEFT JOIN SYSMAN.MGMT_METRIC_COLLECTIONS@XMONC_EMREP18C COLLS ON COLLS.COLL_NAME=MET.COLLECTION_NAME AND COLLS.TARGET_GUID=TAR.TARGET_GUID AND COLLS.METRIC_GUID=C.METRIC_GUID
          LEFT JOIN (select distinct METRIC_GUID, Trim(METRIC_LABEL)  METRIC_LABEL from SYSMAN.MGMT_METRICS@XMONC_EMREP18C) met_lbl on met_lbl.METRIC_GUID=met.METRIC_GUID
   WHERE 
    --Either Warning threshold is defined OR Critical threshold is defined OR Key_Value is defined (e.g. some tablespaces should not be monitored)
    (      TRIM (MET.WARNING_THRESHOLD) IS NOT NULL 
        OR TRIM (MET.CRITICAL_THRESHOLD) IS NOT NULL 
        OR (TRIM(DECODE(MET.COLUMN_LABEL,'User-Defined Numeric Metric',MET.KEY_VALUE2,'User Defined Numeric Metric',MET.KEY_VALUE2,MET.KEY_VALUE)) IS NOT NULL
           )
    )
--    and tar.target_name='olova_dbdpc'
ORDER BY 
    TAR.TARGET_NAME, 
    METRIC,
    Trim(DECODE(met.column_label,'User-Defined Numeric Metric',MET.KEY_VALUE2,'User Defined Numeric Metric',MET.KEY_VALUE2,MET.KEY_VALUE));
COMMIT;

--User defined metrics
SELECT DISTINCT METRIC_LABEL, KEY_VALUE FROM
(
SELECT m.metric_label, M.KEY_VALUE, T.WARNING_THRESHOLD,t.critical_threshold,t.NUM_OCCURENCES,m.target_name,m.target_type,m.collection_timestamp,m.value
FROM SYSMAN.MGMT$METRIC_CURRENT@XMONC_EMREP18C M,
SYSMAN.MGMT_METRIC_THRESHOLDS@XMONC_EMREP18C T
WHERE M.METRIC_GUID=T.METRIC_GUID
AND M.METRIC_LABEL LIKE 'User%Defined%'
AND M.TARGET_GUID=T.TARGET_GUID
--AND M.TARGET_NAME='alamo_dbdpc'
)
ORDER BY 1,2;

--rollback;
--Display date/time of last and previos collections
prompt "Date/time of last and previous collections"
  select 
   (select to_char(max(DATE_COLLECTED),'dd.mm.yyyy hh24:mi')  from ACS_METRIC_THRESH_HIST) LAST_COLLECTION_DATE,
   (select to_char(max(DATE_COLLECTED),'dd.mm.yyyy hh24:mi') from ACS_METRIC_THRESH_HIST where DATE_COLLECTED<(select max(DATE_COLLECTED)  from ACS_METRIC_THRESH_HIST)) PREV_COLLECTION_DATE
  FROM DUAL;

-- List of targets in last collection
select distinct DATE_COLLECTED, target_type,host_name, target_name,groups_grid from ACS_METRIC_THRESH_HIST 
where NVL(GROUPS_GRID,'XXX')<>'XMON' 
  and DATE_COLLECTED=(select max(DATE_COLLECTED)  from ACS_METRIC_THRESH_HIST)
  and target_type like 'oracle_golden%' and host_name='lemva.cgs.sbrf.ru'
order by target_type,host_name, target_name;
  
set linesize 2000 pagesize 1000
col Current_Critical_threshold heading 'Current|Critical|Threshold' format a17
col "Previous Critical threshold" heading "Previous|Critical|Threshold" format a17
col "Current Warning threshold" heading "Current|Warning|Threshold" format a17
col "Previous Warning threshold" heading "Previous|Warning|Threshold" format a17
col "Comparison Operation" heading "Comparison|Operation" format a10
col "Key Value" format a14
col "Metric" format a33
col "Host name" format a20
col "Target name" format a20
col "Target type" format a15
col "Warning threshold changed" heading "Warning|threshold|changed" format a10
col "Critical threshold changed" heading "Critical|threshold|changed" format a10
BREAK ON "Target name" ON "Metric"
--UPDATE ACS_METRIC_THRESH_HIST SET COLLECTION_FREQUENCY=REPLACE(COLLECTION_FREQUENCY,'Minutes','Min') WHERE COLLECTION_FREQUENCY LIKE '%Minutes%';
--commit;
-- Compare all thresholds with previous report (does NOT include added/deleted targets)
prompt "Compare all thresholds with previous report (does NOT include added/deleted targets)"
with 
CUR_DATE as 
(  
  SELECT 
   (select max(DATE_COLLECTED)  from ACS_METRIC_THRESH_HIST) CUR_DATE,
   (select max(DATE_COLLECTED) from ACS_METRIC_THRESH_HIST where DATE_COLLECTED<(select max(DATE_COLLECTED)  from ACS_METRIC_THRESH_HIST)) PREV_DATE
  from dual
)
,
dblist_cur as
(
  select /*+NO_MERGE*/ * from ACS_METRIC_THRESH_HIST where NVL(GROUPS_GRID,'XXX')<>'XMON' 
  and DATE_COLLECTED=(SELECT CUR_DATE FROM CUR_DATE)
) 
,
DBLIST_PREV AS   
(
  SELECT MAX(DATE_COLLECTED) DATE_COLLECTED, 
         TARGET_TYPE, 
         TARGET_NAME,
         GROUPS_GRID,
         HOST_NAME,
         METRIC,
         KEY_VALUE,
         COMPARISON_OPERATOR,
         WARNING_THRESHOLD,
         CRITICAL_THRESHOLD,
         OCCURRENCE_COUNT,
         COLLECTION_FREQUENCY,
         IS_ENABLED
  FROM ACS_METRIC_THRESH_HIST WHERE NVL(GROUPS_GRID,'XXX')<>'XMON' 
  --AND DATE_COLLECTED >(SELECT CUR_DATE FROM CUR_DATE)-20  --Changes for last XX days
  --AND DATE_COLLECTED <(SELECT CUR_DATE FROM CUR_DATE)
--  AND TARGET_NAME='eksmb_eksmb1'
--  AND Key_value='User I/O'
  and DATE_COLLECTED=(SELECT PREV_DATE FROM CUR_DATE)
  GROUP BY TARGET_TYPE, 
         TARGET_NAME,
         GROUPS_GRID,
         HOST_NAME,
         METRIC,
         KEY_VALUE,
         COMPARISON_OPERATOR,
         WARNING_THRESHOLD,
         CRITICAL_THRESHOLD,
         OCCURRENCE_COUNT,
         COLLECTION_FREQUENCY,
         IS_ENABLED
),
NEW_TARGETS AS
(
  SELECT DISTINCT CUR.TARGET_NAME FROM DBLIST_CUR CUR LEFT JOIN DBLIST_PREV PRV ON PRV.TARGET_NAME=CUR.TARGET_NAME WHERE PRV.TARGET_NAME IS NULL
)
,
DELETED_TARGETS AS
(
 SELECT DISTINCT PRV.TARGET_NAME FROM DBLIST_PREV PRV LEFT JOIN DBLIST_CUR CUR ON PRV.TARGET_NAME=CUR.TARGET_NAME WHERE CUR.TARGET_NAME IS NULL
)
SELECT
--      NVL( PRV.TARGET_TYPE,CUR.TARGET_TYPE) "Target type",  
      NVL( PRV.TARGET_NAME,CUR.TARGET_NAME) "Target name",  
--      NVL( PRV.HOST_NAME,CUR.HOST_NAME) "Host name",
      NVL( PRV.METRIC,CUR.METRIC) "Metric",
      NVL( PRV.KEY_VALUE,CUR.KEY_VALUE) "Key Value",
      NVL( PRV.COMPARISON_OPERATOR,CUR.COMPARISON_OPERATOR) "Comparison Operation",
      CASE WHEN NVL(CUR.WARNING_THRESHOLD,'0')<>NVL(PRV.WARNING_THRESHOLD,'0') THEN 
                '''' || PRV.WARNING_THRESHOLD || ''' --> ''' || CUR.WARNING_THRESHOLD || ''''
           ELSE CUR.WARNING_THRESHOLD 
      END "Warning threshold change",
      CASE WHEN NVL(CUR.CRITICAL_THRESHOLD,'0')<>NVL(PRV.CRITICAL_THRESHOLD,'0') THEN 
                '''' || PRV.CRITICAL_THRESHOLD || ''' --> ''' || CUR.CRITICAL_THRESHOLD || ''''
           ELSE CUR.CRITICAL_THRESHOLD 
      END "Critical threshold change",
      CASE WHEN NVL(CUR.IS_ENABLED,1)||CUR.COLLECTION_FREQUENCY <> NVL(PRV.IS_ENABLED,1)||PRV.COLLECTION_FREQUENCY THEN
                '''' || DECODE(PRV.IS_ENABLED,0,'Disabled',PRV.COLLECTION_FREQUENCY) || ''' --> ''' || DECODE(CUR.IS_ENABLED,0,'Disabled',CUR.COLLECTION_FREQUENCY) || ''''
           ELSE CUR.COLLECTION_FREQUENCY
      END "Collection schedule change",
      --PRV.WARNING_THRESHOLD "Previous Warning threshold",
      --CUR.WARNING_THRESHOLD "Current Warning threshold",
      --PRV.CRITICAL_THRESHOLD "Previous Critical threshold",
      --CUR.CRITICAL_THRESHOLD Current_Critical_threshold,
      --CASE WHEN NVL(CUR.WARNING_THRESHOLD,'0')<>NVL(PRV.WARNING_THRESHOLD,'0') THEN 'Yes' END "Warning threshold changed",
      --case when NVL(CUR.CRITICAL_THRESHOLD,'0')<>NVL(PRV.CRITICAL_THRESHOLD,'0') then 'Yes' end "Critical threshold changed" 
      CASE WHEN NVL(CUR.WARNING_THRESHOLD,'0')<>NVL(PRV.WARNING_THRESHOLD,'0') AND NVL(CUR.CRITICAL_THRESHOLD,'0')<>NVL(PRV.CRITICAL_THRESHOLD,'0') THEN 'Warn, Crit'
           WHEN NVL(CUR.WARNING_THRESHOLD,'0')<>NVL(PRV.WARNING_THRESHOLD,'0') AND NVL(CUR.CRITICAL_THRESHOLD,'0')=NVL(PRV.CRITICAL_THRESHOLD,'0') THEN 'Warning'
           WHEN NVL(CUR.WARNING_THRESHOLD,'0')=NVL(PRV.WARNING_THRESHOLD,'0') AND NVL(CUR.CRITICAL_THRESHOLD,'0')<>NVL(PRV.CRITICAL_THRESHOLD,'0') THEN 'Critical'
      END "What changed",
      To_char(PRV.DATE_COLLECTED,'dd.mm.yyyy') "Date collected prv"
FROM DBLIST_PREV PRV 
     FULL OUTER JOIN DBLIST_CUR CUR ON PRV.TARGET_NAME=CUR.TARGET_NAME AND CUR.METRIC=PRV.METRIC AND NVL(CUR.KEY_VALUE,'1')=NVL(PRV.KEY_VALUE,'1') 
     LEFT JOIN DELETED_TARGETS DEL ON DEL.TARGET_NAME=PRV.TARGET_NAME
     LEFT JOIN NEW_TARGETS NNN ON NNN.TARGET_NAME=CUR.TARGET_NAME
WHERE 
      NNN.TARGET_NAME IS NULL 
  AND 
  DEL.TARGET_NAME IS NULL
  and 
      (
            NVL(CUR.WARNING_THRESHOLD,'0')<>NVL(PRV.WARNING_THRESHOLD,'0') 
        OR  NVL(CUR.CRITICAL_THRESHOLD,'0')<>NVL(PRV.CRITICAL_THRESHOLD,'0')
        OR  NVL(CUR.IS_ENABLED,1)<>NVL(PRV.IS_ENABLED,1)
        OR  NVL(CUR.COLLECTION_FREQUENCY,'0')<>NVL(PRV.COLLECTION_FREQUENCY,'0')
      )
ORDER BY PRV.DATE_COLLECTED desc, 
        NVL( PRV.TARGET_NAME,CUR.TARGET_NAME),
        NVL(PRV.METRIC,CUR.METRIC),
        NVL( PRV.KEY_VALUE,CUR.KEY_VALUE);

select * from ACS_METRIC_THRESH_HIST where target_Name='klyazma4_eksmb2' order by date_collected desc;
-- Compare Group membership with previous collection (also includes added targets and deleted targets)
prompt "Compare Group membership with previous collection (also includes added targets and deleted targets)"
col "Previous Group" format a30
col "Current Group" format a30
col "Target name" format a35
with 
CUR_DATE as 
(  
  SELECT 
   (SELECT MAX(DATE_COLLECTED)  FROM ACS_METRIC_THRESH_HIST) CUR_DATE,
   (SELECT MAX(DATE_COLLECTED) FROM ACS_METRIC_THRESH_HIST WHERE DATE_COLLECTED<(SELECT MAX(DATE_COLLECTED)  FROM ACS_METRIC_THRESH_HIST)) PREV_DATE
   --(select max(DATE_COLLECTED) from ACS_METRIC_THRESH_HIST where DATE_COLLECTED<sysdate-30) PREV_DATE
  from dual
)
,
dblist_cur as
(
  select DISTINCT TARGET_TYPE,TARGET_NAME,HOST_NAME,GROUPS_GRID from ACS_METRIC_THRESH_HIST where NVL(GROUPS_GRID,'XXX')<>'XMON' 
  and DATE_COLLECTED=(SELECT CUR_DATE FROM CUR_DATE)
  order by 1,2
) 
,
dblist_prev as   
(
  SELECT DISTINCT DATE_COLLECTED, TARGET_TYPE, TARGET_NAME, HOST_NAME, GROUPS_GRID  FROM ACS_METRIC_THRESH_HIST WHERE NVL(GROUPS_GRID,'XXX')<>'XMON' 
  --AND DATE_COLLECTED<(SELECT CUR_DATE FROM CUR_DATE)   AND DATE_COLLECTED>sysdate-30 -- Last 30 days
  AND DATE_COLLECTED=(SELECT PREV_DATE FROM CUR_DATE)  -- Previous collection
  order by 2,3
)
SELECT
      DISTINCT
      PRV.DATE_COLLECTED,
      NVL( PRV.TARGET_TYPE,CUR.TARGET_TYPE) "Target type",  
      NVL( PRV.TARGET_NAME,CUR.TARGET_NAME) "Target name",  
      NVL( PRV.HOST_NAME,CUR.HOST_NAME) "Host name",
      PRV.GROUPS_GRID "Previous Group",
      CUR.GROUPS_GRID "Current Group",
      CASE WHEN PRV.TARGET_NAME IS NULL THEN 'Target added'
           WHEN CUR.TARGET_NAME IS NULL THEN 'Target deleted'
           WHEN CUR.TARGET_NAME is not null and PRV.TARGET_NAME is not null and NVL(CUR.GROUPS_GRID,'0')<>NVL(PRV.GROUPS_GRID,'0') THEN 'Group membership changed' END "Operation"
from DBLIST_PREV PRV 
     FULL OUTER JOIN DBLIST_CUR CUR ON PRV.TARGET_NAME=CUR.TARGET_NAME 
WHERE 
     NVL(CUR.GROUPS_GRID,'0')<>NVL(PRV.GROUPS_GRID,'0') OR CUR.TARGET_NAME IS NULL OR PRV.TARGET_NAME IS NULL
ORDER BY PRV.DATE_COLLECTED desc, NVL( PRV.HOST_NAME,CUR.HOST_NAME), NVL( PRV.TARGET_NAME,CUR.TARGET_NAME);

--History of threshold change for single target 
--!!!NB: Target name is mentioned 3 times
SELECT 
  DATE_COLLECTED,
  TARGET_TYPE,
  TARGET_NAME,
  HOST_NAME,
  METRIC,
  NVL(KEY_VALUE,'(not specified)') KEY_VALUE,
  COMPARISON_OPERATOR,
  WARNING_THRESHOLD,
  CRITICAL_THRESHOLD
  FROM ACS_METRIC_THRESH_HIST h
  WHERE 
  --NVL(GROUPS_GRID,'XXX')<>'XMON' 
  TARGET_NAME='dnestr-zub_fsbzub'
  --and metric='Average Users Waiting Count'
  AND DATE_COLLECTED=(SELECT MAX(DATE_COLLECTED)  FROM ACS_METRIC_THRESH_HIST)
  UNION ALL
SELECT 
  DATE_COLLECTED,
  TARGET_TYPE,
  TARGET_NAME,
  HOST_NAME,
  METRIC,
  NVL(KEY_VALUE,'(not specified)'),
  COMPARISON_OPERATOR,
  WARNING_THRESHOLD,
  CRITICAL_THRESHOLD
  FROM ACS_METRIC_THRESH_HIST h
  WHERE TARGET_NAME='dnestr-zub_fsbzub' 
  --and metric='Average Users Waiting Count'
  and (METRIC,
  KEY_VALUE,
  COMPARISON_OPERATOR,
  WARNING_THRESHOLD,
  CRITICAL_THRESHOLD) NOT IN (SELECT METRIC,
  KEY_VALUE,
  COMPARISON_OPERATOR,
  WARNING_THRESHOLD,
  CRITICAL_THRESHOLD FROM ACS_METRIC_THRESH_HIST H1 WHERE H1.TARGET_NAME='dnestr-zub_fsbzub' AND H1.DATE_COLLECTED=(SELECT MAX(DATE_COLLECTED)  FROM ACS_METRIC_THRESH_HIST))
  ORDER BY DATE_COLLECTED desc ,METRIC,KEY_VALUE;
  
-- Latest thresholds - flat table for all targets and metrics
select Metric,TARGET_TYPE,
  TARGET_NAME,
  HOST_NAME,
  --METRIC,
  --NVL(KEY_VALUE,'(not specified)') KEY_VALUE,
  --COMPARISON_OPERATOR,
  WARNING_THRESHOLD,
  CRITICAL_THRESHOLD,
  DECODE(IS_ENABLED,0,'Disabled',COLLECTION_FREQUENCY) COLLECTION_FREQUENCY
  FROM ACS_METRIC_THRESH_HIST WHERE NVL(GROUPS_GRID,'XXX')<>'XMON' 
  AND DATE_COLLECTED=(SELECT MAX(DATE_COLLECTED)  FROM ACS_METRIC_THRESH_HIST)
  --AND TARGET_TYPE LIKE 'oracle_g%' --Golden Gate
  AND METRIC='Failed Login Count'
  --AND METRIC IN ('Average (5 min) time for "log file parallel write" waitevent, ms','5 min IO write amount for "log file parallel write" event, Mb','Count of times LGWR waited over 100 ms for last 5 minutes','Count of times LGWR waited over 500 ms for last 5 minutes')
  ORDER BY Host_name, TARGET_TYPE,Target_name,Metric,Key_Value;


-- Latest thresholds - human readable report for all targets
with 
CUR_DATE as 
(  
  SELECT 
   (select max(DATE_COLLECTED)  from ACS_METRIC_THRESH_HIST) CUR_DATE
  from dual
)
,
dblist_cur as
(
  select /* +NOMERGE */ TARGET_TYPE,
  TARGET_NAME,
  HOST_NAME,
  METRIC,
  NVL(KEY_VALUE,'(not specified)') KEY_VALUE,
  COMPARISON_OPERATOR,
  WARNING_THRESHOLD,
  CRITICAL_THRESHOLD,
  DECODE(IS_ENABLED,0,'Disabled',COLLECTION_FREQUENCY) COLLECTION_FREQUENCY
  from ACS_METRIC_THRESH_HIST where NVL(GROUPS_GRID,'XXX')<>'XMON' AND HOST_NAME not in ('m6ekstest1.cgs.sbrf.ru','m6ekstest2.cgs.sbrf.ru','erie1-2.cgs.sbrf.ru','xmon3.cgs.sbrf.ru','erie3.cgs.sbrf.ru','erie1-1.cgs.sbrf.ru')

  and DATE_COLLECTED=(SELECT CUR_DATE FROM CUR_DATE)
),
mtr as 
(Select distinct TARGET_TYPE, METRIC, nvl(key_value,'(not specified)') key_value FROM dblist_cur),
TRG AS 
(Select distinct TARGET_TYPE, TARGET_name,host_name FROM dblist_cur),
full_join as 
(
Select /* +NOMERGE */ trg.TARGET_TYPE,trg.target_name,trg.host_name,mtr.metric, mtr.key_value
 from 
  mtr join trg on trg.target_type=mtr.target_type
  --order by 1,3,2,4;
)
,
mtr_full as 
(
SELECT /* +NOMERGE */
      f.TARGET_TYPE,  
      F.TARGET_NAME,
      f.host_name,
      f.METRIC,
      f.key_value,
      CUR.COMPARISON_OPERATOR,
      CUR.WARNING_THRESHOLD,
      CUR.CRITICAL_THRESHOLD,
      COLLECTION_FREQUENCY
FROM full_join f left join DBLIST_CUR CUR on f.metric=cur.metric and f.TARGET_TYPE=cur.TARGET_TYPE and f.key_value=cur.key_value and f.target_name=cur.target_name
--ORDER BY 1,3,4,2,5;
WHERE 
f.METRIC NOT IN ('Average Users Waiting Count','Database Time Spent Waiting (%)','Active sessions by waitclass')
--  f.TARGET_TYPE='oracle_database'
),
mtr_grp
as 
(
select 
  TARGET_TYPE,
  METRIC,
  key_value,
  COMPARISON_OPERATOR,
  WARNING_THRESHOLD,
  CRITICAL_THRESHOLD,
  COLLECTION_FREQUENCY,
  count(*) Cnt,
  row_number() over (partition by TARGET_TYPE,METRIC,key_value order by count(*) desc) Rank 
FROM MTR_FULL
GROUP BY TARGET_TYPE,METRIC,key_value,COMPARISON_OPERATOR,WARNING_THRESHOLD,CRITICAL_THRESHOLD,COLLECTION_FREQUENCY
--order by TARGET_TYPE,METRIC,key_value,Rank,COMPARISON_OPERATOR,WARNING_THRESHOLD,CRITICAL_THRESHOLD;
),
def_thr as --Default thresholds (thresholds which has maximum number of targets assigned)
(
select 
TARGET_TYPE,
'Default value' target_name,
METRIC,
key_value,
COMPARISON_OPERATOR,
WARNING_THRESHOLD,
CRITICAL_THRESHOLD,
COLLECTION_FREQUENCY,
Cnt "Count of targets"
from 
MTR_GRP 
WHERE RANK=1 AND COMPARISON_OPERATOR IS NOT NULL
),
nondef_thr as 
(
select 
  mtr_full.TARGET_TYPE,
  MTR_FULL.TARGET_NAME,
  mtr_full.host_name,
  mtr_full.METRIC,
  mtr_full.key_value,
  mtr_full.COMPARISON_OPERATOR,
  mtr_full.WARNING_THRESHOLD,
  MTR_FULL.CRITICAL_THRESHOLD,
  MTR_FULL.COLLECTION_FREQUENCY,
  Cnt "Count of targets"
FROM MTR_FULL JOIN MTR_GRP ON MTR_FULL.TARGET_TYPE=MTR_GRP.TARGET_TYPE AND MTR_FULL.METRIC=MTR_GRP.METRIC  AND MTR_FULL.KEY_VALUE=MTR_GRP.KEY_VALUE AND NVL(MTR_FULL.COMPARISON_OPERATOR,'0')=NVL(MTR_GRP.COMPARISON_OPERATOR,'0')
and nvl(mtr_full.WARNING_THRESHOLD,'null')=nvl(mtr_grp.WARNING_THRESHOLD,'null') and nvl(mtr_full.CRITICAL_THRESHOLD,'null') = nvl(mtr_grp.CRITICAL_THRESHOLD,'null') and nvl(mtr_full.COLLECTION_FREQUENCY,'null') = nvl(mtr_grp.COLLECTION_FREQUENCY,'null')
WHERE MTR_GRP.RANK>1 
),
report_lines as 
(
SELECT TARGET_TYPE, METRIC,1 "Default",KEY_VALUE,TARGET_NAME,null "Host name",COMPARISON_OPERATOR "Operator",WARNING_THRESHOLD "Warning",CRITICAL_THRESHOLD "Critical",COLLECTION_FREQUENCY,"Count of targets" 
FROM DEF_THR
--WHERE TARGET_TYPE like 'oracle_g%'
UNION ALL
SELECT TARGET_TYPE, METRIC,null "Default", KEY_VALUE,TARGET_NAME,host_name,COMPARISON_OPERATOR,WARNING_THRESHOLD,CRITICAL_THRESHOLD,COLLECTION_FREQUENCY,"Count of targets" 
FROM NONDEF_THR
--WHERE --TARGET_TYPE='oracle_database'
--WHERE TARGET_TYPE like 'oracle_g%'
--AND TARGET_NAME='ural_unibus'
--AND METRIC NOT IN ('Average Active Sessions')
--and "Count of targets"<10
--not (target_type='oracle_database' and metric='Tablespace Space Used (%)' and comparison_operator is null)
)
select 
  case when nvl(lag(target_Type,1) over (order by target_type,metric,"Default",key_value),'zz')<>target_type then target_type end "Target type",
  case when nvl(lag(METRIC,1) over (order by target_type,metric,"Default",key_value),'zz')<>METRIC then METRIC end "Metric",
  case when nvl(lag(key_value,1) over (order by target_type,metric,"Default",key_value),'zz')<>key_value then key_value end "Metric key value",
  TARGET_NAME "Target name",
  "Host name",
  case when nvl(lag(METRIC,1) over (order by target_type,metric,"Default",key_value),'zz')<>METRIC then "Operator" end "Operator",
  "Warning",
  "Critical",
  COLLECTION_FREQUENCY,
  "Count of targets" "Count of targets" 
from report_lines  
order by target_type,metric,"Default",key_value,NVL("Critical","Warning"),"Host name";

SELECT
      CUR.TARGET_TYPE "Target type",  
      CUR.TARGET_NAME "Target name",  
      CUR.HOST_NAME "Host name",
      CUR.METRIC "Metric",
      CUR.KEY_VALUE "Key Value",
      CUR.COMPARISON_OPERATOR "Comparison Operation",
      CUR.WARNING_THRESHOLD "Warning threshold",
      CUR.CRITICAL_THRESHOLD "Critical threshold"
FROM DBLIST_CUR CUR 
WHERE 
      (
        CUR.WARNING_THRESHOLD is not null OR CUR.CRITICAL_THRESHOLD is not null
      )
ORDER BY "Target type", "Metric", "Target name", "Key Value";

--Massive delete of monitoring targets
select 'emcli delete_target -name="' || target_name || '" -type="oracle_listener"' "script" FROM  SYSMAN.MGMT$TARGET
where target_name like '%chalna%'
and  target_type='oracle_listener';