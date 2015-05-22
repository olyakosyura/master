#!/bin/bash

while :
do
    echo "Starting $1"
    ./$1/script/$1 daemon -l $2 &
    echo -n "$! " >> $3
    wait
    ERRCODE=$?
    if [ $ERRCODE == 98 ]; then
        echo "Already running"
        break
    fi

    LOGS=$(tail -100 ./$1/log/development.log | sed ':a;N;$!ba;s/\n/<br>/g')
    cat <<END > /tmp/report$1
Date: %DATE%
From: Web-Vesna error report system <%FROM_ADDRESS%>
To: %TO_ADDRESS%
Subject: Web-Vesna error report
MIME-Version: 1.0
Content-Type: text/html

<html>
    <head></head>
    <body>
        <b>Date: $(date)<br>
        Program: $1<br>
        Listening: $2<br>
        Return code: $ERRCODE<br></b><br>
        <xmp>$LOGS</xmp>
    </body>
</html>
END
    echo "Sending error report (retcode = $ERRCODE)"
    cat /tmp/report$1 | swaks --to maximovich.andrey@gmail.com,pberejnoy2005@gmail.com --from no-reply@web-vesna.ru --data -
    sleep 5
done
