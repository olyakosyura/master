#!/bin/bash

# default configuration
FRONT_PORT=7000
DATA_PORT=7001
SESSION_PORT=7002
LOGIC_PORT=7003

. config

pidsf='.pids'
if [[ -f .pids ]]
then
    pids=`cat $pidsf`
    kill -9 $pids
    sleep 3
fi

echo -n "" > $pidsf
for var in 'session' 'logic' 'data' 'front'
do
    path=$(echo -n $var | perl -ne '$_ = uc $_;  printf "\"http://127.0.0.1:\$$_%s", "_PORT\""')
    path=$(eval "echo $path")
    ./$var/script/$var daemon -l $path &
    echo -n "$! " >> $pidsf
done
