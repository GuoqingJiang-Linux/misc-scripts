#!/bin/bash

LINUX_TREE=/home/gjiang/xfs-space/linux
CANONICAL_TREE=/home/gjiang/xfs-space/canonical
DEDUP_CODENAME=noble
INPUT_FILE=/tmp/candidates-deduped-6.10
OUTPUT_FILE=/tmp/candidates-check
LAST_STEP=false
CUR_PWD=$PWD

usage() {
echo -e "\nUSAGE: $0 -c codename -i input_file -o output_file -l true
Eg: ./dedup-candidates-per-stable.sh -c noble -i /tmp/candidates-deduped-6.10 -o /tmp/candidates-check -l false\n
echo -e "l" - OUTPUT_FILE only records commit if it is 'false', otherwise both commit and subject
              are recorded if 'true'\n"
exit 1;
}

dedup_sru_commits() {
	CODENAME=$1
	DEDUP_IN_FILE=$2
	DEDUP_OUT_FILE=$3
	FINAL=$4 # true if it is the last dedup then record both hash and subject

	# from codename to the relevant kernel tree
	UBUNTU_KERNEL=$CANONICAL_TREE/$CODENAME
	BASE_VERSION=6.8
	echo $UBUNTU_KERNEL
	cd $UBUNTU_KERNEL
	git checkout master-next
	git reset --hard v${BASE_VERSION}
	git pull

	# dedup against master-next commits which had been merged by previous stable kernel
	cat $DEDUP_IN_FILE | while read commit1
	do
		# check subject for SRU commits instead of SHA1
		cd $LINUX_TREE
		SUBJECT=$(git show $commit1|head -5|tail -1|sed -e 's/^[ \t]*//g')
		#printf "$commit1 $SUBJECT \n"

		cd $UBUNTU_KERNEL
		NOT_DUP=$(git log v${BASE_VERSION}..HEAD --oneline | grep -F "$SUBJECT")
		if [ ! -n "$NOT_DUP" ]; then
			#echo $commit1 not deduped
			if [ "$FINAL" = "false" ]; then
                                echo ${commit1} >> $DEDUP_OUT_FILE
                        else
				cd $LINUX_TREE
                                git show -s --format="%ci %h %s" $commit1 >> $DEDUP_OUT_FILE
                        fi
		else
			echo $commit1 is deduped
		fi
	done
	cd $CURR_PWD
}

while getopts c:i:o:l:h arg
do
	case $arg in
	  c)
                echo "to dedup with canonical kernel codename $OPTARG"
                DEDUP_CODENAME=$OPTARG
                ;;
          i)
                echo "input file: $OPTARG"
                INPUT_FILE=$OPTARG
                ;;
          o)
                echo "output file: $OPTARG"
                OUTPUT_FILE=$OPTARG
                ;;
          l)
                echo "last step: $OPTARG"
                LAST_STEP=$OPTARG
                ;;
	  h|:|?)
		usage
        esac
done

echo DEDUP_CODENAME=$DEDUP_CODENAME INPUT_FILE=$INPUT_FILE OUTPUT_FILE=$OUTPUT_FILE LAST_STEP=$LAST_STEP
# dedup the commits which had been SRUed
if [ "$DEDUP_CODENAME" = "noble" ]; then
	echo dedup SRUed patch in noble
	dedup_sru_commits "noble" "$INPUT_FILE" "$OUTPUT_FILE" "$LAST_STEP"
fi
