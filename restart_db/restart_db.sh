#!/bin/ksh
#/lfs/oracle_temp/mbazgout/restart_db.sh
#Restart database gracefully (with blackout in  GRID and suspend of Tivoli monitoring)
#usage: /lfs/oracle_temp/mbazgout/restart_db.sh ORACLE_SID TECH_EMAIL CUST_EMAIL
#Change log:
#2013-08-27 : mbazgout : First version released


# check usage
if [ $# = "0" ]; then
  echo "usage: restart_db.sh ORACLE_SID [technician_email] [customer_email]"
  exit 1
fi

if [[ $# > 0 ]]; then
    DB_NAME=$1
fi

EMAIL_ACTIVE=0
if [[ $# > 1 ]]; then
  EMAIL_ADDR=$2
  EMAIL_ACTIVE=1
fi

EMAIL2_ACTIVE=0
if [[ $# > 2 ]]; then
  EMAIL2_ADDR=$3
  EMAIL2_ACTIVE=1
fi

###Log file name
LOG_FILE=/tmp/`date +"%F-%H-%M"`-restart-${DB_NAME}.log
START_TIME=`date +"%F %T"`
SERVER_NAME=`uname -n`

## send mail "Restart initiated"
if [ "${EMAIL_ACTIVE}" == "1" ]; then
        echo "Restart of $DB_NAME initiated on host ${SERVER_NAME} at ${START_TIME}" |mailx -s "Restart of $DB_NAME initiated on host ${SERVER_NAME} at ${START_TIME}" -r "oracleop@volvocars.com" $EMAIL_ADDR
else
     echo "Restart of $DB_NAME initiated on host ${SERVER_NAME} at ${START_TIME}" 
     echo Log file is $LOG_FILE
fi

#Send email to customer
if [ "${EMAIL2_ACTIVE}" == "1" ]; then
        echo "Restart of $DB_NAME initiated on host ${SERVER_NAME} at ${START_TIME}" |mailx -s "Restart of $DB_NAME initiated on host ${SERVER_NAME} at ${START_TIME}" -r "oracleop@volvocars.com" $EMAIL2_ADDR
fi

#begin blackout in Grid
. /home/oracle/fifo/bin/set_sid -i agent11g
emctl start blackout ${DB_NAME}_restart $DB_NAME -d 00:30 >$LOG_FILE
#Pause monitoring in Tivoli
curl http://gbwlx007/itm_ora_maint.pl -d rad_1=Enable -d db_name=$DB_NAME -d period=30

#stop database
. /home/oracle/fifo/bin/set_sid -i $DB_NAME
#Setting environment for correct restart of  dpomnip database
if [ -x /home/oracle/.profile ]; then
. /home/oracle/.profile
fi

if [ -x /home/oracle/.profile-env ]; then
. /home/oracle/.profile-env
fi

#Shutdown immediate attempt with timeout 5 minutes
/lfs/oracle_mount/script/misc/timeout.sh -t 300 $ORACLE_HOME/bin/sqlplus /nolog @shu_immediate.sql  >> $LOG_FILE 2>&1

RUNSTATUS=`ps -ef | awk '$NF ~ /^ora_pmon_'${ORACLE_SID}'$/'`
if [ ! -z "${RUNSTATUS}" ]; then
   echo "" >> $LOG_FILE
   echo "==================   Failed to shutdown database with IMMEDIATE option for 5 minutes. Trying to perform shutdown ABORT" >> $LOG_FILE
   /lfs/oracle_mount/script/misc/timeout.sh -t 60 $ORACLE_HOME/bin/sqlplus /nolog @shu_abort.sql >> $LOG_FILE 2>&1
fi   

RUNSTATUS=`ps -ef | awk '$NF ~ /^ora_pmon_'${ORACLE_SID}'$/'`
if [ ! -z "${RUNSTATUS}" ]; then
   echo "" >> $LOG_FILE
   echo "==================   Failed to shutdown database with ABORT option" >> $LOG_FILE
   START_ERR="Failed to shutdown database with ABORT option"
else

  #start database attempt with timeout 120 seconds
  /lfs/oracle_mount/script/misc/timeout.sh -t 120 $ORACLE_HOME/bin/sqlplus /nolog @startup.sql  >> $LOG_FILE 2>&1

  RUNSTATUS=`ps -ef | awk '$NF ~ /^ora_pmon_'${ORACLE_SID}'$/'`
  if [ ! -z "${RUNSTATUS}" ]; then
     echo "Instance ${ORACLE_SID} is running. checking the open mode."
      OPEN_MODE=`sqlplus -s "/ as sysdba" <<EOF
                  set pagesize 0 feedback off verify off heading off echo off
                  SELECT open_mode FROM v\\$database;
                  exit
EOF`
    echo ""  >>$LOG_FILE
    echo "=============   OPEN_MODE=${OPEN_MODE}" >>$LOG_FILE
    echo "OPEN_MODE=${OPEN_MODE}"

    # check the open mode of the database
    if [ "${OPEN_MODE}" != "READ WRITE" ]; then
      START_ERR="Failed to open database"
    fi

  else
     START_ERR="Failed to start instance" 
  fi 
fi

#end blackout
. /home/oracle/fifo/bin/set_sid -i agent11g
emctl stop blackout ${DB_NAME}_restart >> $LOG_FILE

#Resume monitoring in Tivoli
curl http://gbwlx007/itm_ora_maint.pl -d rad_1=Disable -d db_name=$DB_NAME
FINISH_TIME=`date +"%F %T"`
#Send email to technician
if [ ${EMAIL_ACTIVE} == "1" ]; then
  if [ -z $START_ERR ]; then
	cat $LOG_FILE | mailx -s "Restart of $DB_NAME finished at ${FINISH_TIME}" -r "oracleop@volvocars.com" $EMAIL_ADDR
  else 
        cat $LOG_FILE | mailx -s "Restart of $DB_NAME FAILED (${START_ERR}) at ${FINISH_TIME}" -r "oracleop@volvocars.com" $EMAIL_ADDR
  fi
else
  if [ -z $START_ERR ]; then
    echo Restart of $DB_NAME finished at ${FINISH_TIME}
  else
    echo Restart of $DB_NAME FAILED at ${FINISH_TIME} 
  fi
    echo Log file is $LOG_FILE
fi


#Send email to customer if restart succeeded
if [ -z $START_ERR ]; then
  if [ ${EMAIL2_ACTIVE} == "1" ]; then
        echo "Restart of $DB_NAME finished at ${FINISH_TIME}" | mailx -s "Restart of $DB_NAME finished at ${FINISH_TIME}" -r "oracleop@volvocars.com" $EMAIL2_ADDR
  fi
fi


