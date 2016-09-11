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
# Author: Sascha Dittmann (based on the script from Cognosys Technologies for Ubuntu)

###
### Warning! This script partitions and formats disk information be careful where you run it
###          This script is currently under development
###          This script is not currently idempotent and only works for provisioning at the moment

help()
{
  #TODO: Add help text here
  echo "This script installs kafka cluster on RedHat"
  echo "Parameters:"
  echo "-v zookeeper version like 3.4.8"
  echo "-z zookeeper id"
  echo "-i zookeeper Private IP address prefix"
  echo "-c number of zookeeper instances"
  echo "-h view this help content"
}

log()
{
  # If you want to enable this logging add a un-comment the line below and add your account key
  #curl -X POST -H "content-type:text/plain" --data-binary "$(date) | ${HOSTNAME} | $1" https://logs-01.loggly.com/inputs/[account-key]/tag/redis-extension,${HOSTNAME}
  echo "$1"
}

log "Begin execution of zookeeper script extension on ${HOSTNAME}"

if [ "${UID}" -ne 0 ];
then
  log "Script executed without root permissions"
  echo "You must be root to run this program." >&2
  exit 3
fi

# TEMP FIX - Re-evaluate and remove when possible
# This is an interim fix for hostname resolution in current VM
grep -q "${HOSTNAME}" /etc/hosts
if [ $? -eq $SUCCESS ];
then
  echo "${HOSTNAME} found in /etc/hosts"
else
  echo "${HOSTNAME} not found in /etc/hosts"
  # Append it to the hsots file if not there
  echo "127.0.0.1 $(hostname)" >> /etc/hosts
  log "hostname ${HOSTNAME} added to /etc/hosts"
fi

#Script Parameters
ZOOKEEPER_VERSION="3.4.8"
ZOOKEEPER_ID=1
ZOOKEEPER_IP_PREFIX="10.0.0.4"
ZOOKEEPER_INSTANCE_COUNT=1

#Loop through options passed
while getopts :v:z:i:c:h optname; do
    log "Option $optname set with value ${OPTARG}"
  case $optname in
    v)  #zookeeper version
      ZOOKEEPER_VERSION=${OPTARG}
      ;;
    z)  #zookeeper id
      ZOOKEEPER_ID=${OPTARG}
      ;;
    i)  #zookeeper Private IP address prefix
      ZOOKEEPER_IP_PREFIX=${OPTARG}
      ;;
    c) # number of zookeeper instances
        ZOOKEEPER_INSTANCE_COUNT=${OPTARG}
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

# Expand a list of successive IP range defined by a starting address prefix (e.g. 10.0.0.4) and the number of machines in the range
# 10.0.0.4-3 would be converted to "10.0.0.40 10.0.0.41 10.0.0.42"
expand_ip_range_for_server_properties() {
  IFS='-' read -a HOST_IPS <<< "$1"
  for (( n=0 ; n<("${HOST_IPS[1]}"+0) ; n++))
  do
    echo "server.$(expr ${n} + 1)=${HOST_IPS[0]}${n}:2888:3888" >> zookeeper-${ZOOKEEPER_VERSION}/conf/zoo.cfg
  done
}

# Install Oracle Java
log "Installing Java"

# redhat java install
cd /tmp
wget --no-cookies --no-check-certificate --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" "http://download.oracle.com/otn-pub/java/jdk/8u102-b14/jdk-8u102-linux-x64.rpm"
wget --no-cookies --no-check-certificate --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" "http://download.oracle.com/otn-pub/java/jdk/8u102-b14/jre-8u102-linux-x64.rpm"

#Install packages
rpm -Uvh jdk-8u102-linux-x64.rpm
rpm -Uvh jre-8u102-linux-x64.rpm

# Install Zookeeper
log "Installing Zookeeper"

mkdir -p /var/lib/zookeeper
cd /var/lib/zookeeper

zooversion=${ZOOKEEPER_VERSION}
src_package="zookeeper-${zooversion}.tar.gz"
download_url=http://mirrors.ukfast.co.uk/sites/ftp.apache.org/zookeeper/zookeeper-${zooversion}/${src_package}

if [[ ! -f "${src_package}" ]]; then
  log "Downloading Zookeeper"
  wget ${download_url}
fi
log "Extracting Zookeeper"
tar -xvf ${src_package}

touch zookeeper-${zooversion}/conf/zoo.cfg

log "Updating zoo.cfg"
echo "tickTime=2000" >> zookeeper-${zooversion}/conf/zoo.cfg
echo "dataDir=/var/lib/zookeeper" >> zookeeper-${zooversion}/conf/zoo.cfg
echo "clientPort=2181" >> zookeeper-${zooversion}/conf/zoo.cfg
echo "initLimit=5" >> zookeeper-${zooversion}/conf/zoo.cfg
echo "syncLimit=2" >> zookeeper-${zooversion}/conf/zoo.cfg
$(expand_ip_range_for_server_properties "${ZOOKEEPER_IP_PREFIX}-${ZOOKEEPER_INSTANCE_COUNT}")

log "Creating myid"
echo $((ZOOKEEPER_ID+1)) >> /var/lib/zookeeper/myid

log "Updating firewall settings"
# set active firewall setting
firewall-cmd --zone=public --add-port=2181/tcp
firewall-cmd --zone=public --add-port=2888/tcp
firewall-cmd --zone=public --add-port=3888/tcp
firewall-cmd --zone=public --add-port=3888/udp

# set permanent firewall setting
firewall-cmd --zone=public --add-port=2181/tcp --permanent
firewall-cmd --zone=public --add-port=2888/tcp --permanent
firewall-cmd --zone=public --add-port=3888/tcp --permanent
firewall-cmd --zone=public --add-port=3888/udp --permanent

log "Starting Zookeeper"
zookeeper-${zooversion}/bin/zkServer.sh start
