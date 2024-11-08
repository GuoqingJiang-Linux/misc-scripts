#!/bin/bash

LINUX_STABLE_TREE=/home/gjiang/xfs-space/linux-stable
DEDUP_STABLE_VERSION=6.6
INPUT_FILE=/tmp/candidate-commits
OUTPUT_FILE=/tmp/candidates-deduped
LAST_STEP=false
CUR_PWD=$PWD


usage() {
echo -e "\nUSAGE: $0 -d stable_version -i input_file -o output_file -l true
Eg: ./dedup-candidates-per-stable.sh -d 6.6 -i /tmp/candidate-commits -o /tmp/candidates-deduped -l false\n
echo -e "l" - OUTPUT_FILE only records commit if it is 'false', otherwise both commit and subject
	      are recorded if 'true'\n"
exit 1;
}

check_stable_kernel_tag() {
	cd $LINUX_STABLE_TREE
	git pull
	git tag | grep -w "v${1}$" > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "The tag can't be find in stable kernel repo"
		cd $CURR_PWD
		exit 1
	fi
	cd $CURR_PWD
}

dedup_stable_commits() {
	STABLE_VERSION=v$1
	DEDUP_IN_FILE=$2
	DEDUP_OUT_FILE=$3
	FINAL=$4 # true if it is the last dedup then record both hash and subject
	echo $1 $2 $3 $4

	# NOTE the branch need to be existed by run the cmd like this
	# 'git checkout -b linux-6.8.y origin/linux-6.8.y'
	git checkout linux-${1}.y
	#git pull
	# dedup commits which had been merged by previous stable kernel
	cat $DEDUP_IN_FILE | while read commit1
	do
		#echo $commit1 $STABLE_VERSION IN=$DEDUP_IN_FILE OUT=$DEDUP_OUT_FILE
		# TODO better matching
		NOT_DUP=$(git log ${STABLE_VERSION}..HEAD | grep "$commit1" | grep commit |grep pstream)
		#echo $NOT_DUP
		if [ ! -n "$NOT_DUP" ]; then
			cd $LINUX_TREE # commit might not in stable tree if it is pretty new
			if [ "$FINAL" = "false" ]; then
				echo ${commit1} >> $DEDUP_OUT_FILE
			else
				commit_summary=$(git show -s --format="%ci %h %s" $commit1)
				#commit_summary=$(git show --pretty=format:"%h %s" --no-patch $commit1)
				echo ${commit_summary} >> $DEDUP_OUT_FILE
			fi
			cd $LINUX_STABLE_TREE
		fi
	done
}


while getopts d:i:l:o:h arg
do
	case $arg in
	  d)
		echo "to dedup with stable kernel version $OPTARG"
		DEDUP_STABLE_VERSION=$OPTARG
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

echo DEDUP_STABLE_VERSION: $DEDUP_STABLE_VERSION INPUT_FILE: $INPUT_FILE OUTPUT_FILE: $OUTPUT_FILE
check_stable_kernel_tag "$DEDUP_STABLE_VERSION"

cd $LINUX_STABLE_TREE
dedup_stable_commits "$DEDUP_STABLE_VERSION" "$INPUT_FILE" "$OUTPUT_FILE" "$LAST_STEP"

if [ "$LAST_STEP" = "true" ]; then
	# "-u (--unique)" - output only the first of an equal run in case there is redundent?
	#sort -k 1 -u $OUTPUT_FILE -o $OUTPUT_FILE
	sort -k 5 $OUTPUT_FILE -o $OUTPUT_FILE
fi
