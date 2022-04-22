#!/bin/bash
# setenv.sh is oraenv launcher with couple checks
# Denis Shaidullin <Denis.Shaidullin.GDC@ts.fujitsu.com>
#
# Prerequisites: oraenv in $PATH
# Don't forget to create alias for this script: alias setenv='source <script directory>/setenv.sh'
#
# Change tracking
# fork from cluster_envset 1.2 to rac_envset 1.0
# 1.1 names like %CHZ_ excluded from instance list

# set traditional sorting order
export LC_ALL=C

if [ -z "$1" ]
then
  # use oratab to find SIDs #remove empty line# remove leading spaces       #remove comments  # print only SIDs         # exclude like %CHZ_    # sorting
  SID_LIST=`cat /etc/oratab | grep -v -e '^$' |  sed -e 's/^[[:space:]]*//' | grep -v -e '^#' | awk -F ":" '{print $1}' | grep -vE "_CHZ[1-4]$" | sort`
  for SID in $SID_LIST ; do
      # if Instance isn't running then color red
          ps -ef  | grep pmon_$SID$ > /dev/null
      if  [ $? -eq  0 ]
      then
        echo -e "    $SID"
      else
        echo -e "    \e[0;31m$SID\e[0m"
      fi
  done

  echo -n "Enter SID: "
  read USER_SID
else
  USER_SID=$1
fi

# check USER_SID
cat /etc/oratab | grep -v -e '^$' |  sed -e 's/^[[:space:]]*//' | grep -v -e '^#' | grep -vE "_CHZ[1-4]$" | awk -F ":" '{print $1}' | grep -e "^$USER_SID$" > /dev/null
if  [ $? -eq  0 ]
then
  export ORACLE_SID=$USER_SID
  export ORAENV_ASK=NO
  source oraenv
  unset ORAENV_ASK
  export PATH=$ORACLE_HOME/OPatch:$PATH

  echo ""
  echo -e "========== Oracle variables \e[0;32msuccessfully changed\e[0m =========="
  echo -e "ORACLE_HOME:  $ORACLE_HOME"
  echo -e "ORACLE_SID :  $ORACLE_SID"
  echo "==========================================================="
  echo ""
else
  echo ""
  echo -e "============= Oracle variables \e[0;31mnot changed\e[0m ================"
  echo -e "Invalid SID \e[0;31m$USER_SID\e[0m"
  echo -e "ORACLE_HOME:  $ORACLE_HOME"
  echo -e "ORACLE_SID :  $ORACLE_SID"
  echo "==========================================================="
  echo ""
fi

