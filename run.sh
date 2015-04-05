#!/bin/bash

# default configuration
FRONT_PORT=6000
DATA_PORT=6001
SESSION_PORT=6002

. config

pidsf='.pids'
if [[ -f .pids ]]
then
    pids=`cat $pidsf`
    kill -9 $pids
    sleep 1
fi

echo -n "" > $pidsf
for var in 'session' 'front'
do
    path=$(echo -n $var | perl -ne '$_ = uc $_;  printf "\"http://127.0.0.1:\$$_%s", "_PORT\""')
    path=$(eval "echo $path")
    ./$var/script/$var daemon -l $path &
    echo -n "$! " >> $pidsf
done
