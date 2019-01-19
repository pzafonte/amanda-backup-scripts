#!/bin/sh

#############################################################
# Author : Peter Zafonte                                    #
# Purpose: Create Disk Entry(DLE) for amanda configuration  #
# Date   : Apr 09,2015                                      #
# Files  : /etc/amanda/template.d/disklist                  #
#          /var/lib/amanda/bin/createdle.sh                 #
# Usage  : ./createdle.sh [OPTIONS] -t zfs-dumptype config  #
#          zfs-dumptype: snapshot, sendrecv                 #
# Sample : ./createdle.sh -i ~/.ssh/id_rsa_amanda \         #
#                        snapshot  MonthlySet               #
#############################################################

#0. define const & variables
ZFS_SERVER="hoth-internal"
AMANDA_CONF_DIR="/etc/amanda"
DLE_CONS="$AMANDA_CONF_DIR/template.d/disklist"
DLE_TEMP="$AMANDA_CONF_DIR/template.d/disklist_temp"
EXCLUDE_DLE="$AMANDA_CONF_DIR/template.d/exclude.dle"
SSH_ID="amandabackup"
SSH_ID_KEY="/var/lib/amandabackup/.ssh/id_rsa"

#1. check command line
#1.1 show usage:
showusage(){
 echo "This script get all zfs file system entries from a solaris system and convert them to disk entry list in amanda configuration"
 echo "usage:"
 echo "./fetchdle.sh [OPTIONS] -t zfs-dumptype -s zfs-server amanda_config"
 echo "OPTIONS:"
 echo "  -l username, default amandabackup"
 echo "  -i ssh_key,  default ~/.ssh/id_rsa"
 echo "zfs-dumptype:"
 echo "  snapshot"
 echo "  sendrecv"
 exit ${EXITPROB}
}


if [ $# -lt 3 ]
then
    showusage
fi

while getopts ":l:i:t:s:" option;
do
    case $option in
        l ) SSH_ID=$OPTARG;;
        i ) SSH_ID_KEY=$OPTARG;;
        t ) ZFS_DUMP=$OPTARG;;
	s ) ZFS_SERVER=$OPTARG;;
        \?) showusage;;
    esac
done
shift $(($OPTIND - 1))
AMANDA_CONF="$AMANDA_CONF_DIR/$*" 

if [ ! -d "$AMANDA_CONF" ]
then
    echo "Amanda configuration $AMANDA_CONF doesn't exist"
    exit 1
fi    

if [ "$ZFS_DUMP" != "snapshot" ] && [ "$ZFS_DUMP" != "sendrecv" ]
then
    echo "$ZFS_DUMP is not valid"
    exit 1
fi

#2. retrieve zfs file system entries
if [ ${ZFS_DUMP} = "snapshot" ] 
then
    COL="zfsname"
else
    COL="mountpoint"
fi


ssh -l $SSH_ID -i $SSH_ID_KEY $ZFS_SERVER "java bin/HomeList $COL" > $DLE_TEMP


#3. combite zfs and template dle and copy to destination configuration fold
AMANDA_CONF_DLE="$AMANDA_CONF/disklist"

buildzfsdle() {
    local zfsdump="zfs-$1"
    while read line
    do
        # grep "$line" $EXCLUDE_DLE > /dev/null
        DLE_ENTRY=0
        # exclude entries on exlude list file
        while read keyword
        do
            if [ "$keyword" = "$line" ]
            then
		DLE_ENTRY=1
 		break
            fi
    	done < $EXCLUDE_DLE
        
        # exclude entries containing .restore.
        echo $line |grep "/restore" > /dev/null
        if [ "$?" -eq 0 ]
        then
             DLE_ENTRY=1
        fi

        if [ "$DLE_ENTRY" -eq 1 ]
        then
            echo "The entry is excluded from the DLE: $line"
            continue
        fi
        echo "$ZFS_SERVER       $line           $zfsdump" >> $AMANDA_CONF_DLE
    done < $DLE_TEMP
}

buildzfsdle $ZFS_DUMP

# delete temporary files
rm $DLE_TEMP

