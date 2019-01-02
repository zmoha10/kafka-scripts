#!/bin/bash

# The MIT License (MIT)
#
# Copyright (c) 2015 Microsoft Azure
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# Author: Cognosys Technologies

###
### Warning! This script partitions and formats disk information be careful where you run it
###          This script is currently under development and has only been tested on Ubuntu images in Azure
###          This script is not currently idempotent and only works for provisioning at the moment

### Remaining work items
### -Alternate discovery options (Azure Storage)
### -Implement Idempotency and Configuration Change Support
### -Recovery Settings (These can be changed via API)

help()
{
    #TODO: Add help text here
    echo "This script installs kafka cluster on Ubuntu"
    echo "Parameters:"
    echo "-k kafka version like 0.8.2.1"
    echo "-b broker id"
    echo "-h view this help content"
    echo "-z zookeeper not kafka"
    echo "-i zookeeper Private IP address prefix"
    echo "-m id to be used in myid file"
}

log()
{
	# If you want to enable this logging add a un-comment the line below and add your account key
    	#curl -X POST -H "content-type:text/plain" --data-binary "$(date) | ${HOSTNAME} | $1" https://logs-01.loggly.com/inputs/[account-key]/tag/redis-extension,${HOSTNAME}
	echo "$1"
}

log "Begin execution of kafka script extension on ${HOSTNAME}"

if [ "${UID}" -ne 0 ];
then
    log "Script executed without root permissions"
    echo "You must be root to run this program." >&2
    exit 3
fi

# TEMP FIX - Re-evaluate and remove when possible
# This is an interim fix for hostname resolution in current VM
grep -q "${HOSTNAME}" /etc/hosts
if [ "$?" -eq 0 ];
then
  echo "${HOSTNAME}found in /etc/hosts"
else
  echo "${HOSTNAME} not found in /etc/hosts"
  # Append it to the hsots file if not there
  echo "127.0.0.1 $(hostname)" >> /etc/hosts
  log "hostname ${HOSTNAME} added to /etc/hosts"
fi

#Script Parameters
CONFLUENT_VERSION="5.0.1"
BROKER_ID=0
ZOOKEEPER1KAFKA0="0"

ZOOKEEPER_IP_PREFIX="10.10.0.10"
INSTANCE_COUNT=1
ZOOKEEPER_PORT="2181"
MYID="0"

#Loop through options passed
while getopts :k:b:z:i:c:m:h optname; do
    log "Option $optname set with value ${OPTARG}"
  case $optname in
    k)  #confluent version
      CONFLUENT_VERSION=${OPTARG}
      ;;
    b)  #broker id
      BROKER_ID=${OPTARG}
      ;;
    z)  #zookeeper not kafka
      ZOOKEEPER1KAFKA0=${OPTARG}
      ;;
    i)  #zookeeper Private IP address prefix
      ZOOKEEPER_IP_PREFIX=${OPTARG}
      ;;
    c) # Number of instances
	    INSTANCE_COUNT=${OPTARG}
	    ;;
    m) # myid
      MYID=${OPTARG}
      ;;
    h)  #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      help
      exit 2
      ;;
  esac
done

echo "before install Java code"

# Install Oracle Java
install_java()
{
  log "Installing OpenJDK Java"
  add-apt-repository ppa:openjdk-r/ppa
  apt-get update -y
  apt-get install openjdk-8-jdk -y
}

echo "After install Java code"

# Expand a list of successive IP range defined by a starting address prefix (e.g. 10.0.0.1) and the number of machines in the range
# 10.0.0.1-3 would be converted to "10.0.0.10 10.0.0.11 10.0.0.12"

expand_ip_range_for_server_properties() {
    echo "$1"
    echo "$2"
    IFS='-' read -a HOST_IPS <<< "$1"
    for (( n=0 ; n<"${HOST_IPS[1]}"+0 ; n++))
    do
        echo "server.$(expr ${n} + 1)=${HOST_IPS[0]}${n}:2888:3888" >> /opt/confluent/etc/kafka/zookeeper.properties
        # echo $((${n}+1)) >> /opt/confluent/lib/zookeeper/myid
    done
}

echo "After expand_ip_range_for_server_properties"

function join { local IFS="$1"; shift; echo "$*"; }

expand_ip_range() {
    IFS='-' read -a HOST_IPS <<< "$1"

    declare -a EXPAND_STATICIP_RANGE_RESULTS=()

    for (( n=0 ; n<"${HOST_IPS[1]}"+0 ; n++))
    do
        HOST="${HOST_IPS[0]}${n}:${ZOOKEEPER_PORT}"
                EXPAND_STATICIP_RANGE_RESULTS+=($HOST)
    done

    echo "${EXPAND_STATICIP_RANGE_RESULTS[@]}"
}

download_confluent_oss()
{
  echo "In Download confluent oss"
  cd /opt/
  echo "$PWD"
  # Download the package
  wget http://packages.confluent.io/archive/5.0/confluent-oss-5.0.1-2.11.tar.gz -O confluent-oss.tar.gz

  # untar confluent tar file
  tar -zxvf confluent-oss.tar.gz
  echo | ls

  # rename directory to confluent
  mv confluent-5.0.1 confluent

  # create a logs file in the confluent folder
  mkdir -p confluent/logs
}

# Install Zookeeper - can expose zookeeper version
configure_and_start_zookeeper()
{
  mkdir -p /opt/confluent/lib/zookeeper
  local zookeeper_props_file='/opt/confluent/etc/kafka/zookeeper.properties'
  # cd /opt/confluent
  # echo "" > $zookeeper_props_file
	echo "tickTime=2000" > $zookeeper_props_file
	echo "dataDir=/opt/confluent/lib/zookeeper" >> $zookeeper_props_file
  echo "initLimit=5" >> $zookeeper_props_file
  echo "syncLimit=2" >> $zookeeper_props_file
	echo "clientPort=2181" >> $zookeeper_props_file
	# OLD Test echo "server.1=${ZOOKEEPER_IP_PREFIX}:2888:3888" >> zookeeper-3.4.6/conf/zoo.cfg
	$(expand_ip_range_for_server_properties "${ZOOKEEPER_IP_PREFIX}-${INSTANCE_COUNT}" "$zookeeper_props_file")

  # echo "autopurge.snapRetainCount=3" >> $zookeeper_props_file
  # echo "autopurge.purgeInterval=24" >> $zookeeper_props_file

	echo $(($MYID+1)) > /opt/confluent/lib/zookeeper/myid

  nohup /opt/confluent/bin/zookeeper-server-start "$zookeeper_props_file" >> /opt/confluent/logs/zookeeper-server.log &
	# zookeeper-3.4.9/bin/zkServer.sh start
}

# Install kafka
configure_and_start_kafka()
{
  local kafka_props_file='/opt/confluent/etc/kafka/server.properties'
  local log_dirs='\/opt\/confluent\/kafka-logs'
	sed -r -i "s/(broker.id)=(.*)/\1=${BROKER_ID}/g" $kafka_props_file
	sed -r -i "s/(zookeeper.connect)=(.*)/\1=$(join , $(expand_ip_range "${ZOOKEEPER_IP_PREFIX}-${INSTANCE_COUNT}"))/g" $kafka_props_file
  sed -r -i "s/(log.dirs)=(.*)/\1=${log_dirs}/g" $kafka_props_file
  nohup /opt/confluent/bin/kafka-server-start $kafka_props_file >> /opt/confluent/logs/kafka-server.log &
}

mount_disk()
{
  local fileDisk="$1"
  local filePartition="$2"
  # check if the file partition exists
  df | grep -q "${filePartition}"

  if [ $? -gt 0 ]; then
    # Create Disk partition
    printf "n\np\n1\n\n\nw\n" | fdisk ${fileDisk}
    # Format the disk partition
    mkfs -t ext4 ${filePartition}
    # mount /opt to the partition
    mount ${filePartition}  /opt
    # ghet uuid for filePartition
    local uuid=$(blkid "${filePartition}" | cut -d" " -f2 | tr -d '"')
    # Generate dstab entry and append to /etc/fstab
    local line="${uuid}   /opt   ext4   defaults,nofail   1   2"
    echo $line >> /etc/fstab
  fi
}

mount_disk '/dev/sdc' '/dev/sdc1'

# Primary Install Tasks
#########################
#NOTE: These first three could be changed to run in parallel
#      Future enhancement - (export the functions and use background/wait to run in parallel)

#Install OpenJDK Java
#------------------------
install_java

# Downlaod confluent OSS
download_confluent_oss

if [ ${ZOOKEEPER1KAFKA0} -eq "1" ];
then
  # mount_disk '/dev/sdc' '/dev/sdc1'
	#
	#Install zookeeper
	#-----------------------
	configure_and_start_zookeeper
else
  # mount_disk '/dev/sdc' '/dev/sdc1'
	#
	#Install kafka
	#-----------------------
	configure_and_start_kafka
fi
