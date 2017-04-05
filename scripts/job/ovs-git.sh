#!/bin/bash

set -e

function Check-LastRanFile {
    lastranfile="$WORKSPACE/lastrancommit.txt"
    if [ ! -e $lastranfile ]; then
        echo "LastRanFile doesn't exist. Creating it."
        git -C $WORKSPACE/ovs rev-parse HEAD | tee $WORKSPACE/lastrancommit.txt
        echo "Starting first job for OVS unit tests"
        firstcommit=$(cat $WORKSPACE/lastrancommit.txt)
        curl -X POST "http://{jenkins_user}:{jenkins_pass}@{jenkins_ip}:8080/job/ovs-build-job/buildWithParameters?token={token}&commitid=$firstcommit"
        echo "Job for first commitID $firstcommit started"
    fi
}

function Get-GitLog {
    currentcommit=$(cat $WORKSPACE/lastrancommit.txt)
    commitlog=$(git -C $WORKSPACE/ovs rev-list $currentcommit...HEAD)
    if [ ! "$commitlog" ]; then
        echo "There are no new commits to OVS master. Existing Job."
        exit 0
    fi
    echo "$commitlog" | tee $WORKSPACE/gitlog.txt
    head -1 $WORKSPACE/gitlog.txt | tee $WORKSPACE/lastrancommit.txt
}

function Start-OVSBuildJob {
    while read line
    do
        echo "Starting job for commitID $line"
        curl -X POST "http://{jenkins_user}:{jenkins_pass}@{jenkins_ip}:8080/job/ovs-build-job/buildWithParameters?token={token}&commitid=$line"
        echo "Job for commitID $line started"
    done < $WORKSPACE/gitlog.txt
}

echo "Getting commit ID's and writing them to $WORKSPACE/gitlog.txt"

Check-LastRanFile

Get-GitLog

Start-OVSBuildJob