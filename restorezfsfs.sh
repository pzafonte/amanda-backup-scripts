#!/bin/sh

#############################################################
# Author  : Peter Zafonte                                   #
# Purpose : Restore zfs-sendrecv backup package             #
# Date    : April 17,2015                                   #
# Package : netcat on amanda & zfs systems                  #
# Usage   : ./restorezfsfs.sh                               #
#############################################################

#0. define const & variables
ZFS_SERVER="vader-internal"
DLE_PREFIX="/export/home"
SSH_ID="amandabackup"
SSH_KEY="/var/amandabackup/.ssh/id_rsa"
RESTORE_TIME=`date --date yesterday +%Y-%m-%d`

#1. check command line
#1.1 show usage
showusage(){
 echo "This script automates the process of restoring zfs-sendrecv backup package " 
 echo "usage:"
 echo "`basename ${0}` [OPTIONS]"
 echo "OPTIONS:"
 echo "    -h show usage"
 echo "    -H zfs file system server"
 echo "    -u restore username"
 echo "    -t restore timestamp (YYYY-MM-DD)"
 echo "    -l username to logon zfs file system(amandabackup)"
 echo "    -i ssh key to logon zfs file system(/var/lib/amanda/.ssh/id_rsa)"
 echo ${EXITPROB}
 exit 1
}

#1.2 accept CLI
while getopts "hH:u:t:l:i:" opt
do
    case $opt in
        h ) showusage;;
	H ) ZFS_SERVER=$OPTARG;;
	u ) RESTORE_NAME=$OPTARG;;
  	t ) RESTORE_TIME=$OPTARG;;
	l ) SSH_ID=$OPTARG;;
	i ) SSH_KEY=$OPTARG;;
	\?) showusage;;
    esac
done

shift $(($OPTIND - 1))
AMANDA_CONFIG=$*	
if [ "$AMANDA_CONFIG" = "" ]
then
 AMANDA_CONFIG="DailySet1"
fi

if [ ! $RESTORE_NAME ]
then
    showusage
fi

showpara(){
 echo "zfs_server: $ZFS_SERVER"
 echo "restore_name: $RESTORE_NAME"
 echo "restore_time: $RESTORE_TIME"
 echo "SSH_ID: $SSH_ID"
 echo "ssh_key: $SSH_KEY"
 echo "config:  $AMANDA_CONFIG"
} 

# showpara

#2.find the required backup pacakges 
#2.1 valid server 
ping -c 1 $ZFS_SERVER &> /dev/null 
if [ "$?" -ne 0 ]
then
   echo "$ZFS_SERVER is not alive"
   exit 1
fi

#2.2 valid file system(full name Vs user account)
#2.2.1 define the user zfs name & mountpoint and restore zfs name & mountpoint
IS_FULLDLE=`expr index $RESTORE_NAME "/"`
if [ "$IS_FULLDLE" -gt 0 ]
then
 DLE=$RESTORE_NAME
else
 DLE="$DLE_PREFIX/$RESTORE_NAME"
fi
DLE_PARENT=${DLE%/*}
USERID=${DLE##*/}
echo ssh -i $SSH_KEY $SSH_ID@$ZFS_SERVER "/usr/sbin/zfs list -H -o name $DLE_PARENT ||echo 'ERROR'"
ZFS_PARENT_FS=`ssh -i $SSH_KEY $SSH_ID@$ZFS_SERVER "/usr/sbin/zfs list -H -o name $DLE_PARENT ||echo 'ERROR'"`
echo "zfs parent: $ZFS_PARENT_FS"
if [ "$ZFS_PARENT_FS" = "ERROR" ]
then
   echo "$RESTORE_NAME is invalid"
   exit 1
fi
USER_DIR=${ZFS_PARENT_FS}/${USERID}
USER_RESTORE_HOME="${USER_DIR}.`date +%Y%m%d`"
RESTORE_TO_FS=`echo $USER_RESTORE_HOME |sed -e "s/home/restore/"`
echo "Name restored zfs file system: $RESTORE_TO_FS"

#2.2.2 check if the zfs file system exist on server
IS_FS_AVAI=`ssh -i $SSH_KEY $SSH_ID@$ZFS_SERVER "/usr/sbin/zfs list -H -o name $RESTORE_TO_FS 2> /dev/null"` 
if [ "$IS_FS_AVAI" = "$RESTORE_TO_FS" ]
then
  echo "Error: the file system $RESTORE_TO_FS already exists on $ZFS_SERVER"
  exit 1
fi

#2.3 check the tape and restore to user.restore.retore_date file system
#2.3.1  find the matched tape based on timestamp
echo "Start searching backup tapes..."
TMP_FILE_AMADMIN="/tmp/.amadmin.$USERID"
/usr/sbin/amadmin $AMANDA_CONFIG find --sort hkD $ZFS_SERVER $DLE | grep "OK" > $TMP_FILE_AMADMIN
NUM_REC=`cat $TMP_FILE_AMADMIN |wc -l`
if [ "$NUM_REC" -lt 1 ]
then
  echo "No backup record for $DLE on $RESTORE_TIME" 
  exit 1
fi
TMP_FILE_TAPE="/tmp/.datelist.$USERID"
/bin/echo -n "" > $TMP_FILE_TAPE
while read EACHREC
do
  BKUP_LEVEL=`echo $EACHREC |cut -d' ' -f5`
  RESTORE_TIME_FMT=`echo $RESTORE_TIME |sed -e "s/-//g"`
  TAPE_TIME_FMT=`echo $EACHREC|cut -d' ' -f1 |sed -e "s/-//g"`
  if [ "$RESTORE_TIME_FMT" -lt "$TAPE_TIME_FMT" ]
  then
	continue
  fi
  TAPE_ITEM=`echo $EACHREC|cut -d' ' --output-delimiter='' -f1,2 |sed -e "s/-//g" |sed -e "s/://g"`
  cat "$TMP_FILE_TAPE" |grep "$TAPE_ITEM"
  if [ "$?" -ne 0 ] && [ "$BKUP_LEVEL" != "$PREV_LEVEL" ]
  then
        echo "Tape found: $EACHREC"
	echo "$BKUP_LEVEL $TAPE_ITEM" >> $TMP_FILE_TAPE
  fi
  if [ "$BKUP_LEVEL" -eq 0 ]
  then
 	break
  fi
  PREV_LEVEL=$BKUP_LEVEL
done < $TMP_FILE_AMADMIN
rm $TMP_FILE_AMADMIN

#2.3.2 restore the file system from backup
echo "Start restoring..."
TMP_FILE_TAPE_SORT="${TMP_FILE_TAPE}.sort"
sort $TMP_FILE_TAPE > $TMP_FILE_TAPE_SORT
rm $TMP_FILE_TAPE
while read EACHTAPE
do
  RESTORE_TAPE_ID=`echo $EACHTAPE |cut -d' ' -f2`
  RESTORE_LEVEL=`echo $EACHTAPE |cut -d' ' -f1`
  ssh -f -i $SSH_KEY $SSH_ID@$ZFS_SERVER "/opt/csw/bin/nc -lp 3333 |/usr/bin/pfexec /usr/sbin/zfs recv -F ${RESTORE_TO_FS}@level${RESTORE_LEVEL}"
  sleep 1
  amfetchdump -lpa $AMANDA_CONFIG $ZFS_SERVER $DLE $RESTORE_TAPE_ID |gunzip |pv -b |/bin/nc 172.16.89.5 3333 -q 0
  echo "level${RESTORE_LEVEL} restored successfully"
done < $TMP_FILE_TAPE_SORT
rm $TMP_FILE_TAPE_SORT
HOME_DIR=`ssh -i $SSH_KEY $SSH_ID@$ZFS_SERVER "/usr/sbin/zfs list -H -o mountpoint ${RESTORE_TO_FS}"`
echo "$USERID's file system dated on $RESTORE_TIME has been restored at $HOME_DIR, please logon deathstar to copy files to ~${USERID}/restore.`date +%Y%m%d`" 
