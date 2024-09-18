#!/bin/bash
# run under linux repo

# find from the specific commit or tag
START_POINT=v6.8
LINUX_TREE=/home/gjiang/xfs-space/linux
LINUX_STABLE_TREE=/home/gjiang/xfs-space/linux-stable

# record all the commits since START POINT
COMMIT1_FILE=/tmp/phase1-file
# record all the commits which have "Fixes: " tag
COMMIT2_FILE=/tmp/phase2-file

DEDUP_68x_FILE=/tmp/dedup-6.8.x-file
DEDUP_66x_FILE=/tmp/dedup-6.6.x-file
DEDUP_69x_FILE=/tmp/dedup-6.9.x-file

# This file need to be checked by human to backport fix commit
CHECK_FILE=/tmp/check-file

rm $COMMIT1_FILE $COMMIT2_FILE $DEDUP_68x_FILE $DEDUP_66x_FILE $DEDUP_69x_FILE $CHECK_FILE

cd $LINUX_TREE
git pull
git log --no-merges  --oneline $START_POINT.. | cut -d ' ' -f1 > $COMMIT1_FILE
cat $COMMIT1_FILE | while read commit1
do
	IS_FIX=$(git show ${commit1} | grep "Fixes: ")
	if [ ! -n "$IS_FIX" ]; then
		continue
	else
		echo ${commit1} >> $COMMIT2_FILE
	fi
done

cd $LINUX_STABLE_TREE
STABLE_68_BRANCH=linux-6.8.y
git checkout $STABLE_68_BRANCH
git pull
# dedup commits which had been merged by 6.8.x
cat $COMMIT2_FILE | while read commit1
do
	NOT_DUP=$(git log v6.8.. | grep "$commit1")
	if [ ! -n "$NOT_DUP" ]; then
		echo ${commit1} >> $DEDUP_68x_FILE
	else
		continue
	fi
done

STABLE_66_BRANCH=linux-6.6.y
git checkout $STABLE_66_BRANCH
git pull
# dedup commits which had been merged by 6.6.x
cat $DEDUP_68x_FILE | while read commit1
do
	NOT_DUP=$(git log v6.6.. | grep "$commit1")
	if [ ! -n "$NOT_DUP" ]; then
		echo ${commit1} >> $DEDUP_66x_FILE
	else
		continue
	fi
done

STABLE_69_BRANCH=linux-6.9.y
git checkout $STABLE_69_BRANCH
git pull
# dedup commits which had been merged by 6.9.x
cat $DEDUP_66x_FILE | while read commit1
do
	NOT_DUP=$(git log v6.9.. | grep "$commit1")
	if [ ! -n "$NOT_DUP" ]; then
		commit_summary=$(git show --pretty=format:"%h %s" --no-patch $commit1)
		echo ${commit_summary} >> $DEDUP_69x_FILE
	else
		continue
	fi
done

# sort the final file per subsystem
sort -k 2 $DEDUP_69x_FILE > $CHECK_FILE

cd $LINUX_TREE
