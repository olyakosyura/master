#!/bin/bash

# default configuration
FRONT_PORT=7000
DATA_PORT=7001
SESSION_PORT=7002
LOGIC_PORT=7003
FILES_PORT=7004

FRONT_HOST=localhost
DATA_HOST=localhost
SESSION_HOST=localhost
LOGIC_HOST=localhost
FILES_HOST=localhost

export MOJO_REACTOR=Mojo::Reactor::Poll


. config

pidsf='.pids'
pids=`cat $pidsf`
if [ "$1" == "status" ]; then
    if [ "$pids" == "" ]; then
        echo "Nothing started"
    else
        kill -0 $pids
    fi
    exit 0
fi

if [[ -f .pids ]]
then
    if [ "$pids" != "" ]; then
        kill -9 $pids
        sleep 3
    fi
fi

echo -n "" > $pidsf

if [ "$1" == "kill" ]; then
    exit 0
fi

if [ "$1" != "" ]; then
    echo "Available commands: status | kill"
    exit 0
fi

for var in 'session' 'logic' 'data' 'front'
do
    path=$(echo -n $var | perl -ne '$_ = uc $_;  printf "\"http://\$$_%s:\$$_%s\"", "_HOST", "_PORT"')
    path=$(eval "echo $path")
    bash ./real_run.sh $var $path $pidsf &
    echo -n "$! " >> $pidsf
done
