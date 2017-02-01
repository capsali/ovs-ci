#!/bin/bash

set -e

function Check-LastRanFile {
    lastranfile="$WORKSPACE/lastrancommit.txt"
    if [ ! -e $lastranfile ]; then
        echo "LastRanFile doesn't exist. Creating it."
        cd $WORKSPACE/ovs
        git rev-parse HEAD | tee $WORKSPACE/lastrancommit.txt
    fi
}

function Get-GitLog {
    currentcommit=`cat $WORKSPACE/lastrancommit.txt`
    commitlog=`git rev-list $currentcommit...HEAD`
    if [ ! "$commitlog" ]; then
        echo "There are no new commits to OVS master. Existing Job."
        exit 0
    fi
    echo "$commitlog" | tee $WORKSPACE/gitlog.txt
    head -1 $WORKSPACE/gitlog.txt | tee $WORKSPACE/lastrancommit.txt
}

function Start-CommitJob {
    while read line
    do
        echo "Starting job for commitID $line"
        curl -X POST "http://$jenk_user:$jenk_api@10.20.1.3:8080/job/ovs-build-job/buildWithParameters?token=b204eee759ab38ebb986d223f6c5b4ce&commitid=$line"
        echo "Job for commitID $line started"
    done < $WORKSPACE/gitlog.txt
}

export WORKSPACE="/var/lib/jenkins/jobs/master-job/workspace"

echo "Getting commit ID's and writing them to $WORKSPACE/gitlog.txt"

Check-LastRanFile

cd $WORKSPACE/ovs

Get-GitLog

Start-CommitJob