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
echo -e "\nUSAGE: $0 -b base_ker_ver -p pre_ker_ver -a after_ker_ver
Eg: ./find-fix-commits.sh -b 6.8 -p 6.6 -a 6.9 or just run without pass any
arguments which use default values '-b 6.8 --p 6.6 -a 6.9'. Note: the value
of them should be ascending: pre_ker_ver -> base_ker_ver -> after_ker_ver,
one exception when '0' is passed to pre_ker_ver or after_ker_ver then we do
not dedup against such relevant kernel. Note the relevant stable kernel
branch such as linux-6.8.y should be checkouted before\n"

echo -e "'b' - the base commit or version from which people want to find fix commits,
it usually equal with the base kernel version which our kernel start from it.\n"

echo -e "'p' - the previous stable kernel tag which we regularly sync commit from,
which means the fix commits should be deduplicated if it have already been
merged by this stable kernel. And it is same for 'a' while it stands for
stable kernel version after base kernel.\n"
exit 1;
}

check_kernel_tag() {
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
	git pull
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

while getopts b:p:a:h arg
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
		DEDUP_CUR_FILE=/tmp/dedup-${BASE_VERSION}.x-file
		cd $CURR_PWD
		;;
	  p)
		echo "previous stable version: $OPTARG"
		PRE_VERSION=$OPTARG
		if [ $PRE_VERSION == 0 ]; then
			echo "Not check against previous stable kernel"
			continue
		fi
		check_kernel_tag "$PRE_VERSION"
		DEDUP_PRE_FILE=/tmp/dedup-${PRE_VERSION}.x-file
		;;
	  a)
		echo "after stable version: $OPTARG"
		AFTER_VERSION=$OPTARG
		if [ $AFTER_VERSION == 0 ]; then
			echo "Not check against later stable kernel"
			continue
		fi
		check_kernel_tag "$AFTER_VERSION"
		DEDUP_AFTER_FILE=/tmp/dedup-${AFTER_VERSION}.x-file
		;;
	  h|:|?)
		usage
        esac
done

if awk "BEGIN {exit !($BASE_VERSION <= $PRE_VERSION ||
		     ($BASE_VERSION >= $AFTER_VERSION && $AFTER_VERSION != 0))}"; then
	echo "The number of those version are insane"
	echo "Base version $BASE_VERSION, PRE_VERSION $PRE_VERSION, AFTER_VERSION $AFTER_VERSION"
	exit 1
else
	echo "Base version $BASE_VERSION, PRE_VERSION $PRE_VERSION, AFTER_VERSION $AFTER_VERSION"
fi

rm -rf $COMMIT1_FILE $COMMIT2_FILE $DEDUP_CUR_FILE $DEDUP_PRE_FILE $DEDUP_AFTER_FILE $CHECK_FILE
#rm -rf $DEDUP_CUR_FILE $DEDUP_PRE_FILE $DEDUP_AFTER_FILE $CHECK_FILE

# PART I - get all fix commits from BASE_VERSION
cd $LINUX_TREE
git pull
git log --no-merges  --oneline v${BASE_VERSION}.. | cut -d ' ' -f1 > $COMMIT1_FILE
cat $COMMIT1_FILE | while read commit1
do
	IS_FIX=$(git show ${commit1} | grep "Fixes: ")
	if [ ! -n "$IS_FIX" ]; then
		IS_CC_STABLE=$(git show ${commit1} | grep "Cc: stable@vger.kernel.org")
		if [ ! -n "$IS_CC_STABLE" ]; then
			continue
		else
			#echo COMMIT $commit1 was cced to stable
			echo ${commit1} >> $COMMIT2_FILE
		fi
	else
		echo ${commit1} >> $COMMIT2_FILE
	fi
done
echo "PART I is done !"

# PART II - remove fix commits which have been merged by stable kernel which
#	    our kernel sync commits from it regularly
cd $LINUX_STABLE_TREE

# dedup from the stable kernel of current kernel version (also is the base point)
p_result=$(echo "$PRE_VERSION > 0" | bc)
a_result=$(echo "$AFTER_VERSION > 0" | bc)
if [ $p_result -eq 1 ] || [ $a_result -eq 1 ]; then
	dedup_stable_commits "$BASE_VERSION" "$COMMIT2_FILE" "$DEDUP_CUR_FILE" false
	echo either p_result or a_result exists
else
	dedup_stable_commits "$BASE_VERSION" "$COMMIT2_FILE" "$DEDUP_CUR_FILE" true
	echo both p_result and a_result not exist
fi
echo "PART II.1 is done !"

if [ $p_result -eq 1 ]; then
#if [ $PRE_VERSION -ne 0 ]; then
	echo start PART II.2
	if [ $a_result -eq 1 ]; then
#	if [ $AFTER_VERSION -e 0 ] then
		dedup_stable_commits "$PRE_VERSION" "$DEDUP_CUR_FILE" "$DEDUP_PRE_FILE" false
	else
		dedup_stable_commits "$PRE_VERSION" "$DEDUP_CUR_FILE" "$DEDUP_PRE_FILE" true
	fi
fi
echo "PART II.2 is done !"

if [ $a_result -eq 1 ]; then
#if [ $AFTER_VERSION -ne 0 ]; then
	echo start PART II.3
	if [ $p_result -eq 1 ]; then
#	if [ $PRE_VERSION -ne 0 ] then
		dedup_stable_commits "$AFTER_VERSION" "$DEDUP_PRE_FILE" "$DEDUP_AFTER_FILE" true
	else
		dedup_stable_commits "$AFTER_VERSION" "$DEDUP_CUR_FILE" "$DEDUP_AFTER_FILE" true
	fi
fi
echo "PART II.3 is done !"

# sort the final file per subsystem
if [ $a_result -eq 1 ]; then
	# "-u (--unique)" - output only the first of an equal run in case there is redundent?
	sort -k 1 -u $DEDUP_AFTER_FILE -o $DEDUP_AFTER_FILE
	sort -k 5 $DEDUP_AFTER_FILE -o $CHECK_FILE
elif [ $p_result -eq 1 ]; then
	sort -k 1 -u $DEDUP_PRE_FILE -o $DEDUP_PRE_FILE
	sort -k 5 $DEDUP_PRE_FILE -o $CHECK_FILE
else
	sort -k 1 -u $DEDUP_CUR_FILE -o $DEDUP_CUR_FILE
	sort -k 5 $DEDUP_CUR_FILE -o $CHECK_FILE
fi

cd $CURR_PWD
