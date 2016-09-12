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
  echo "This script installs nifi cluster on RedHat"
  echo "Parameters:"
  echo "-v nifi version like 1.0.0"
  echo "-n node id"
  echo "-i node Private IP address"
  echo "-z zookeeper Private IP address prefix"
  echo "-p zookeeper port"
  echo "-c number of zookeeper instances"
  echo "-h view this help content"
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
NODE_ID=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -f1 -d'/' | rev | cut -f1 -d'.' | rev)
NODE_IP=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -f1 -d'/')
ZOOKEEPER_IP_PREFIX="10.0.0.4"
ZOOKEEPER_INSTANCE_COUNT=1
ZOOKEEPER_PORT="2181"

#Loop through options passed
while getopts :v:n:i:z:p:c:h optname; do
  log "Option $optname set with value ${OPTARG}"
  case $optname in
    v)  #nifi version
      NIFI_VERSION=${OPTARG}
      ;;
    n)  #node id
      NODE_ID=${OPTARG}
      ;;
    i)  #node Private IP address prefix
      NODE_IP=${OPTARG}
      ;;
    z)  #zookeeper Private IP address prefix
      ZOOKEEPER_IP_PREFIX=${OPTARG}
      ;;
    p)  #zookeeper port
      ZOOKEEPER_PORT=${OPTARG}
      ;;
    c) # number of Zookeeper instances
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

function join { local IFS="$1"; shift; echo "$*"; }

# Expand a list of successive IP range defined by a starting address prefix (e.g. 10.0.0.1) and the number of machines in the range
# 10.0.0.1-3 would be converted to "10.0.0.10 10.0.0.11 10.0.0.12"
expand_ip_range() {
  IFS='-' read -a HOST_IPS <<< "$1"

  declare -a EXPAND_STATICIP_RANGE_RESULTS=()

  for (( n=0 ; n<("${HOST_IPS[1]}"+0) ; n++))
  do
    HOST="${HOST_IPS[0]}${n}:${ZOOKEEPER_PORT}"
    EXPAND_STATICIP_RANGE_RESULTS+=($HOST)
  done

  echo "${EXPAND_STATICIP_RANGE_RESULTS[@]}"
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

# Increase the limits of File Handles
# NiFi will at any one time potentially have a very large number of file handles open.
echo "*  hard  nofile  50000" >> /etc/security/limits.conf
echo "*  soft  nofile  50000" >> /etc/security/limits.conf

# Increase the allowable number of Forked Processes
# NiFi may be configured to generate a significant number of threads.
echo "*  hard  nproc  10000" >> /etc/security/limits.conf
echo "*  soft  nproc  10000" >> /etc/security/limits.conf
echo "*  soft  nproc  10000" >> /etc/security/limits.d/90-nproc.conf 

# Increase the number of TCP socket ports available
sysctl -w net.ipv4.ip_local_port_range="10000 65000"

# Set how long sockets stay in a TIMED_WAIT state when closed
echo 'net.ipv4.netfilter.ip_conntrack_tcp_timeout_time_wait="1"' >> /etc/sysctl.conf

# Swapping is fantastic for some applications. It isn’t good for something like NiFi that always wants to be running.
echo "vm.swappiness = 0" >> /etc/sysctl.conf
sysctl -w vm.swappiness=0

# Install nifi
log "Installing Nifi"
cd /usr/local
version=${NIFI_VERSION}
src_package="nifi-${version}-bin.tar.gz"
download_url=http://mirrors.ukfast.co.uk/sites/ftp.apache.org/nifi/${version}/${src_package}

rm -rf nifi
mkdir -p nifi
cd nifi
#_ MAIN _#
if [[ ! -f "${src_package}" ]]; then
  log "Downloading Nifi"
  wget ${download_url}
fi
log "Extracting Nifi"
tar -xvf ${src_package}
cd nifi-${version}

log "Updating nifi.properties"
sed -r -i "s/(nifi.cluster.is.node)=(.*)/\1=true/g" conf/nifi.properties
sed -r -i "s/(nifi.cluster.node.address)=(.*)/\1=${NODE_IP}/g" conf/nifi.properties
sed -r -i "s/(nifi.cluster.node.protocol.port)=(.*)/\1=50000/g" conf/nifi.properties
sed -r -i "s/(nifi.zookeeper.connect.string)=(.*)/\1=$(join , $(expand_ip_range "${ZOOKEEPER_IP_PREFIX}-${ZOOKEEPER_INSTANCE_COUNT}"))/g" conf/nifi.properties

log "Install Nifi Service"
bin/nifi.sh install

log "Updating firewall settings"
# set active firewall setting
firewall-cmd --zone=public --add-port=8080/tcp
firewall-cmd --zone=public --add-port=50000/tcp

# set permanent firewall setting
firewall-cmd --zone=public --add-port=8080/tcp --permanent
firewall-cmd --zone=public --add-port=50000/tcp --permanent

log "Starting Nifi"
service nifi start