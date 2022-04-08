echo
hostname
echo ========================
echo 'Total RAM: ' `free -m|grep Mem|awk '{print $2}'` ' Mb'
echo 'Sum of SGA_MAX: ' `/lfs/oracle_mount/script/check/memory_usage.sh|egrep "^Total"|awk '{print $2}'` ' Mb'
echo 'shmall: ' $((`cat /proc/sys/kernel/shmall`*(`getconf PAGE_SIZE`/1024)/1024)) ' Mb'
echo 'shmall: ' `cat /proc/sys/kernel/shmall` ' pages'
egrep "HugePages_Total|HugePages_Rsvd" /proc/meminfo
/lfs/oracle_mount/script/check/hugepage_setting.sh
grep memlock /etc/security/limits.conf |egrep -v "^#"
echo 'Num of databases: ' `ps -ef|grep [p]mon|wc -l`

