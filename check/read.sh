echo -n "Continue with patching [y/n]?"
while read yes_no
do
case $yes_no in
  Y|y) echo "User answered Y"; break ;;
  N|n) echo "User answered N"; exit 2 ;;
  * ) ;; ## Add whatever other tests you need
esac
done

echo -n 'Database shutdown... '
