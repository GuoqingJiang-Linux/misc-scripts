#!/bin/bash

LINUX_TREE=/home/gjiang/xfs-space/linux
LINUX_STABLE_TREE=/home/gjiang/xfs-space/linux-stable
CUR_PWD=$PWD

# record all the commits since the base version
COMMIT1_FILE=/tmp/phase1-file
# record all the commits which have "Fixes: " tag
COMMIT2_FILE=/tmp/phase2-file
# This file need to be checked by human to backport fix commit
CHECK_FILE=/tmp/check-file

BASE_VERSION=6.8
PRE_VERSION=6.6
AFTER_VERSION=6.9
DEDUP_CUR_FILE=/tmp/dedup-${BASE_VERSION}.x-file
DEDUP_PRE_FILE=/tmp/dedup-${PRE_VERSION}.x-file
DEDUP_AFTER_FILE=/tmp/dedup-${AFTER_VERSION}.x-file

usage() {
        echo -e "\nUSAGE: $0 -b base_kernel_ver -p pre_kernel_ver -a after_kernel_ver\n
		example: ./find-fix-commits.sh -b 6.8 -p 6.6 -a 6.9 or just run without\n
		arguments which use the default value -b 6.8 --p 6.6 -a 6.9"
	echo -e "'b' means the commit or tag from which people want to find fix commits, \nit usually equal with the base kernel version which our kernel start from it. "
	echo ""
	echo -e "'p' - the previous stable kernel tag which we regularly sync commit from it, which means the \nfix commits should be deduplicated if it have already been merged by this stable \nkernel. And it is same for 'a' while it is for kernel after base kernel version."
        exit 1;
}

check_kernel_tag() {
	cd $LINUX_STABLE_TREE
	git pull
	git branch -a | grep remote | grep $1 > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "The tag can't be find in stable kernel repo"
		cd $CURR_PWD
		exit 1
	fi
	cd $CURR_PWD
}

dedup_stable_commits() {
	STABLE_VERSION=$1
	DEDUP_IN_FILE=$2
	DEDUP_OUT_FILE=$3
	echo $1 $2 $3

	git checkout linux-${STABLE_VERSION}.y
	git pull
	# dedup commits which had been merged by previous stable kernel
	cat $DEDUP_IN_FILE | while read commit1
	do
		NOT_DUP=$(git log v${STABLE_VERSION}.. | grep "$commit1")
		if [ ! -n "$NOT_DUP" ]; then
			echo ${commit1} >> $DEDUP_OUT_FILE
		else
			continue
		fi
	done
}

while getopts s:p:a: arg
do
	case $arg in
	  b)
		echo "start kernel version is $OPTARG"
		cd $LINUX_TREE
		BASE_VERSION=$OPTARG
		git show v${BASE_VERSION} > /dev/null 2>&1
		if [ $? -ne 0 ]; then
			echo "The argument is not valid which can't be find in kernel repo"
			exit 1
		fi
		DEDUP_CUR_FILE=/tmp/dedup-${BASE_VERSION}.x-file
		cd $CURR_PWD
		;;
	  p)
		echo "previous stable version: $OPTARG"
		PRE_VERSION=$OPTARG
		check_kernel_tag "$PRE_VERSION"
		DEDUP_PRE_FILE=/tmp/dedup-${PRE_VERSION}.x-file
		;;
	  a)
		echo "after stable version: $OPTARG"
		AFTER_VERSION=$OPTARG
		check_kernel_tag "$AFTER_VERSION"
		DEDUP_AFTER_FILE=/tmp/dedup-${AFTER_VERSION}.x-file
		;;
	  :)
		usage
		exit 1
		;;
	  ?)
		usage
		exit 1
		;;
        esac
done

rm -rf $COMMIT1_FILE $COMMIT2_FILE $DEDUP_CUR_FILE $DEDUP_PRE_FILE $DEDUP_AFTER_FILE $CHECK_FILE

# PART I - get all fix commits from BASE_VERSION
cd $LINUX_TREE
git pull
git log --no-merges  --oneline v${BASE_VERSION}.. | cut -d ' ' -f1 > $COMMIT1_FILE
cat $COMMIT1_FILE | while read commit1
do
	IS_FIX=$(git show ${commit1} | grep "Fixes: ")
	if [ ! -n "$IS_FIX" ]; then
		continue
	else
		echo ${commit1} >> $COMMIT2_FILE
	fi
done

echo "PART I is done !"

# PART II - remove fix commits which have been merged by stable kernel which
#	    our kernel sync commits from it regularly
cd $LINUX_STABLE_TREE

# dedup from the stable kernel of current kernel version (also is the start point)
dedup_stable_commits "$BASE_VERSION" "$COMMIT2_FILE" "$DEDUP_CUR_FILE"
echo "PART II.1 is done !"
dedup_stable_commits "$PRE_VERSION" "$DEDUP_CUR_FILE" "$DEDUP_PRE_FILE"
echo "PART II.2 is done !"
dedup_stable_commits "$AFTER_VERSION" "$DEDUP_PRE_FILE" "$DEDUP_AFTER_FILE"
echo "PART II.3 is done !"

# sort the final file per subsystem
sort -k 2 $DEDUP_AFTER_FILE > $CHECK_FILE

cd $CURR_PWD
