echo
hostname
echo ========================
echo 'Sockets: ' `cat /proc/cpuinfo | grep "physical id" | sort -n | uniq | wc -l`
echo 'Cores: ' `cat /proc/cpuinfo | grep "cpu cores" | wc -l`
echo 'Hyperthread cores: ' `cat /proc/cpuinfo | grep "ht" | wc -l`
echo CPU `cat /proc/cpuinfo | grep "model name" | uniq`
echo `cat /proc/cpuinfo | grep "cpu MHz" | uniq`
echo 'Num of databases: ' `ps -ef|grep [p]mon|wc -l`

