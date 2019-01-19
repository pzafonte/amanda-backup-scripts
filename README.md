# amanda-backup-scripts
Scripts written for the Amanda Tape Backup system.

This script get all zfs file system entries from a solaris system and convert them to disk entry list in amanda configuration
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


This script automates the process of restoring zfs-sendrecv backup package 
#############################################################
# Author  : Peter Zafonte                                   #
# Purpose : Restore zfs-sendrecv backup package             #
# Date    : April 17,2015                                   #
# Package : netcat on amanda & zfs systems                  #
# Usage   : ./restorezfsfs.sh                               #
#############################################################



