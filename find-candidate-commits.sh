#!/bin/bash

LINUX_TREE=/home/gjiang/xfs-space/linux
BASE_VERSION=6.8
TMP_FILE=/tmp/tmp-commits
OUTPUT_FILE=/tmp/candidate-commits
CUR_PWD=$PWD

usage() {
echo -e "\nUSAGE: $0 -b base_ker_ver -o output_file
Eg: find-candidate-commits.sh -b 6.8 -o /tmp/candidate-commits\n"

exit 1;
}

while getopts b:o:h arg
do
	case $arg in
	  b)
		echo "base kernel version is $OPTARG"
		cd $LINUX_TREE
		BASE_VERSION=$OPTARG
		git show v${BASE_VERSION} > /dev/null 2>&1
		if [ $? -ne 0 ]; then
			echo "The argument is not valid which can't be find in kernel repo"
			exit 1
		fi
		cd $CURR_PWD
		;;
	  o)
		echo "output file is: $OPTARG"
		OUTPUT_FILE=$OPTARG
		;;
	  h|:|?)
		usage
        esac
done

echo BASE_VERSION=$BASE_VERSION OUTPUT_FILE=$OUTPUT_FILE
cd $LINUX_TREE
git pull
git log --no-merges  --oneline v${BASE_VERSION}.. | cut -d ' ' -f1 > $TMP_FILE
cat $TMP_FILE | while read commit1
do
	IS_FIX=$(git show ${commit1} | grep "Fixes: ")
	if [ ! -n "$IS_FIX" ]; then
		IS_CC_STABLE=$(git show ${commit1} | grep "Cc: stable@vger.kernel.org")
		if [ ! -n "$IS_CC_STABLE" ]; then
			continue
		else
			#echo $commit1 is Cced to stable
			echo ${commit1} >> $OUTPUT_FILE
		fi
	else
		#echo $commit1 has Fixes: tag
		echo ${commit1} >> $OUTPUT_FILE
	fi
done
rm $TMP_FILE
cd $CUR_PWD
