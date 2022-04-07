--Shutdown immediate and exit
connect / as sysdba
whenever sqlerror exit 1
whenever oserror exit 1
startup
exit

