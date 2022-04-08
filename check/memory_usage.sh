#!/bin/bash
#
# Copyright 2010 Fujitsu GDC Russia
#
# program: show_memory_params_all_db.sh
# by Mikhail Bazgoutdinov
#
# Script calculates sum of memory required by all database at the Oracle hotel.
# It shows value of sga_max_size parameter and "maximum PGA allocated" statistics
# modification history:
# date        by        comments
# ----------  --------  ----------------
# 09/06/2010  mbazgout  original program
# 28/06/2010  mbazgout  added Show system wide shared memory limits after list of instances
echo "Calculating memory usage by Oracle databases, all results are in Mb"
echo "==============================================================================================================================="
echo "Database    Max_SGA,Mb  Max_PGA,Mb  PGA target  PGA current SGA target  SGA used    Free SGA    Memor trgt  Theoretical Max, Mb"
echo "==========  ==========  ==========  ==========  ==========  ==========  ==========  ==========  ==========  ==================="



usage()
{
echo "Usage: $0"
}



#
# check usage
#
if [ $# != "0" ];then
  usage;exit 1
fi

ORA_TAB=/etc/oratab
export ORACLE_SID=$1
#get list of database instances
INSTANCES=`$HOME/fifo/bin/db.sh -l`
Total_SGA=0
Total_PGA=0
Total_MEM=0
Total_SGA_tar=0
Total_PGA_cur=0
Total_Free_SGA=0
Total_SGA_use=0
Total_Mem_tar=0
ps -ef | awk '$NF ~ /^ora_pmon_/' >/tmp/mem_usage.$$.tmp
for ORACLE_SID in ${INSTANCES}
do
        DB_PGA=0
        DB_SGA=0
        DB_PGA_tar=0
        DB_SGA_tar=0
        DB_PGA_cur=0
        DB_Free_SGA=0
        DB_SGA_use=0
        DB_Mem_tar=0
        if [ "${ORACLE_SID}" != "agent10g" ]; then
                RUNSTATUS=`cat /tmp/mem_usage.$$.tmp|grep ${ORACLE_SID}`
                #if Database is up then calculate memory size
                if [ ! -z "${RUNSTATUS}" ]; then
                        . $HOME/fifo/bin/set_sid -i ${ORACLE_SID}
                        #Retrieve maximum SGA size from DB
                        DB_SGA=`sqlplus -s "/ as sysdba" <<EOF
                                        set pagesize 0 feedback off verify off heading off echo off
                                        select Round(value/1024/1024) from v\\$parameter where name='sga_max_size';
                                        exit;
EOF`

                        #Retrieve PGA target size from DB
                        DB_PGA_tar=`sqlplus -s "/ as sysdba" <<EOF
                                        set pagesize 0 feedback off verify off heading off echo off
                                        select Round(value/1024/1024) from v\\$parameter where name='pga_aggregate_target';
                                        exit;
EOF`

                        #Retrieve maximum PGA size from DB
                        DB_PGA=`sqlplus -s "/ as sysdba" <<EOF
                                        set pagesize 0 feedback off verify off heading off echo off
                                        select Round(value/1024/1024) from V\\$PGASTAT where Name='maximum PGA allocated';
                                        exit;
EOF`

                        #Retrieve current PGA size from DB
                        DB_PGA_cur=`sqlplus -s "/ as sysdba" <<EOF
                                        set pagesize 0 feedback off verify off heading off echo off
                                        select Round(value/1024/1024) from V\\$PGASTAT where Name='total PGA allocated';
                                        exit;
EOF`

                        #Retrieve SGA target size from DB
                        DB_SGA_tar=`sqlplus -s "/ as sysdba" <<EOF
                                        set pagesize 0 feedback off verify off heading off echo off
                                        select * from (
                                        select 0 sga_target from dual
                                        union all 
                                        select Round(value/1024/1024) from v\\$parameter where name='sga_target'
                                        order by sga_target desc
                                        ) where rownum=1;
                                        exit;
EOF`

                       #Retrieve free SGA from DB
                        DB_Free_SGA=`sqlplus -s "/ as sysdba" <<EOF
                                        set pagesize 0 feedback off verify off heading off echo off
                                        select Round(sum(bytes)/1024/1024)
                                        from v\\$sgastat
                                        where name = 'free memory';
                                        exit;
EOF`

                       #Retrieve SGA used from DB
                        DB_SGA_use=`sqlplus -s "/ as sysdba" <<EOF
                                        set pagesize 0 feedback off verify off heading off echo off
                                        select Round(sum(bytes)/1024/1024)
                                        from v\\$sgastat
                                        where name <> 'free memory';
                                        exit;
EOF`
                        #Retrieve Memory target size from DB
                        DB_Mem_tar=`sqlplus -s "/ as sysdba" <<EOF
                                        set pagesize 0 feedback off verify off heading off echo off
                                        select * from (
                                        select 0 memory_target from dual
                                        union all
                                        select Round(value/1024/1024) from v\\$parameter where name='memory_target'
                                        order by memory_target desc
                                        ) where rownum=1;
                                        exit;
EOF`


                        let "Total_SGA = ${Total_SGA} + ${DB_SGA}"
                        let "Total_SGA_tar = ${Total_SGA_tar} + ${DB_SGA_tar}"
                        let "Total_PGA=${Total_PGA}+${DB_PGA}"
                        let "Total_PGA_cur=${Total_PGA_cur}+${DB_PGA_cur}"
                        let "DB_MEM=${DB_SGA}+${DB_PGA}"
                        let "Total_MEM=${Total_MEM}+${DB_MEM}"
                        let "Total_Free_SGA=${Total_Free_SGA}+${DB_Free_SGA}"
                        let "Total_SGA_use=${Total_SGA_use}+${DB_SGA_use}"
                        let "Total_Mem_tar=${Total_Mem_tar}+${DB_Mem_tar}"

                        echo "${ORACLE_SID} ${DB_SGA} ${DB_PGA} ${DB_PGA_tar} ${DB_PGA_cur} ${DB_SGA_tar} ${DB_SGA_use} ${DB_Free_SGA} ${DB_Mem_tar} ${DB_MEM}"|awk '{printf  "%-11s %-11s %-11s %-11s %-11s %-11s %-11s %-11s %-11s %-11s \n",$1,$2,$3,$4,$5,$6,$7,$8,$9,$10}'
                else
                        echo "${ORACLE_SID}"|awk -v COMMENT="======Database is down=======" '{printf "%-10s %s\n",$1,COMMENT}'
                fi
        fi
done

echo "Total ${Total_SGA} ${Total_PGA} ---- ${Total_PGA_cur} ${Total_SGA_tar} ${Total_SGA_use} ${Total_Free_SGA} ${Total_Mem_tar} ${Total_MEM}"|awk '{printf "%-11s %-11s %-11s %-11s %-11s %-11s %-11s %-11s %-11s %-11s \n",$1,$2,$3,$4,$5,$6,$7,$8,$9,$10}'
echo "==============================================================================================================================="
echo " "
rm /tmp/mem_usage.$$.tmp

#Show system wide shared memory limits
if [ `uname -s` == Linux ]; then
   echo System wide shared memory limit is $((`cat /proc/sys/kernel/shmall`*(`getconf PAGE_SIZE`/1024)/1024)) Mb
   ipcs -lm
   echo "HugePages"
   echo "========="
   egrep "HugePages_Total|HugePages_Rsvd" /proc/meminfo
   HUGE_TOTAL=`grep HugePages_Total /proc/meminfo|awk '{print $2}'`
   HUGE_RSVD=`grep HugePages_Rsvd /proc/meminfo|awk '{print $2}'`
   HUGE_FREE=`grep HugePages_Free /proc/meminfo|awk '{print $2}'`
   let "HUGE_USED=${HUGE_TOTAL}-${HUGE_FREE}+${HUGE_RSVD}"
   echo HugePages_Used:  ${HUGE_USED}
fi


