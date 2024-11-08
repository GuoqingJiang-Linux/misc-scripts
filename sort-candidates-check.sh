# ./sort-candidates-check.sh /tmp/candidates-check

SORTED_DEDUPED_FILE=/tmp/sorted-candidates-check

sort -k 1 -u $1 -o $1
sort -k 5 $1 -o $SORTED_DEDUPED_FILE
# delete the unnecessary info such as '+0100'
cut -d ' ' -f1-2,4- $SORTED_DEDUPED_FILE > /tmp/1
mv /tmp/1 $SORTED_DEDUPED_FILE
