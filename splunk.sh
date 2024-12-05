#!/bin/bash +xx

# splunk_install.sh
#
# developer(s)     : Venu Tadepalli, Josh Westmoreland
# date (refactored): 2020-06-04
# maintainer email : gesos.team@ge.com

# ================================================== VARIABLES ================================================== #

INSTALLER_LOCUS='/tmp'
if [ ! -z "$1" ]; then INSTALLER_LOCUS="$1"; fi

SCRIPTS="/tmp/gesos_source/gesos/image_build/scripts/linux"
LSB_REL='/etc/lsb-release'
RH_REL='/etc/redhat-release'
OS_REL='/etc/os-release'
SPLUNK_VERSION='9.2.1'
SPLUNK_BUILD='78803f08aabb'
# SPLUNK_VERSION='9.1.1'
# SPLUNK_BUILD='64e843ea36b1'
# SPLUNK_VERSION='8.2.5'
# SPLUNK_BUILD='77015bc7a462'
# SPLUNK_VERSION='7.2.9.1'
# SPLUNK_BUILD='605df3f0dfdd'
# BASE_DL_URL='https://download.splunk.com/products/universalforwarder/releases'
INSTALLER_SUFFIX='x86_64.rpm'
INSTALL_CMD='rpm -ivh'
INSTALL_CHECK_CMD='rpm -qa'
SPLUNK='splunk'
SPLUNKF_HOME='/opt/splunkforwarder'
SPLUNK_EXEC="$SPLUNKF_HOME/bin/$SPLUNK"
HOSTNAME="$(cat /etc/hostname)"

if [ -f "$LSB_REL" ] && [[ $(cat "$LSB_REL" | grep DISTRIB_ID=Ubuntu) ]]
then 
  INSTALLER_SUFFIX='amd64.deb'
  INSTALL_CMD='dpkg -i'
  INSTALL_CHECK_CMD='dpkg -l'
fi

INSTALLER="$INSTALLER_LOCUS/splunkforwarder-$SPLUNK_VERSION-$SPLUNK_BUILD-linux-2.6-$INSTALLER_SUFFIX"
# SPLUNK_DOWNLOAD="$BASE_DL_URL/$SPLUNK_VERSION/linux/$INSTALLER"

# ============================================= AZURE METADATA STUFF ============================================ #

# function getMetadata () {
#   BASE_METADATA_URL='http://169.254.169.254/metadata/instance'
#   API_VERSION='api-version=2019-11-01'
#   FORMAT='format=text'
#   CUURENT_REQUEST="$1"

#   curl -s -H Metadata:true "$BASE_METADATA_URL/$CUURENT_REQUEST?$API_VERSION&$FORMAT"
# }

# LOCATION="$(getMetadata 'compute/location')"
# INSTANCE_ID="$(getMetadata 'compute/vmId')"
# LOCAL_IPV4="$(getMetadata 'network/interface/0/ipv4/ipAddress/0/privateIpAddress')"
# INSTANCE_TYPE="$(getMetadata 'compute/vmSize')"
# SUBSCRIPTION_ID="$(getMetadata 'compute/subscriptionId')"

function getMetadata () {
  BASE_METADATA_URL='http://169.254.169.254/metadata/instance'
  API_VERSION='api-version=2019-11-01'
  RETRIES=3
  WAIT=2
  for i in $(seq $RETRIES)
  do
    # store the whole response with the status at the and
    HTTP_RESPONSE=$(curl -H Metadata:true "$BASE_METADATA_URL?$API_VERSION&")
    
    if [ jq -e . >/dev/null 2>&1 <<<"$HTTP_RESPONSE" ]
    then
      echo "Error	"
      # wait for retry
      fuctionResult="Failed"
      sleep $WAIT
    else
      fuctionResult="$HTTP_RESPONSE"
      break
    fi
  done
}
getMetadata
if [[ $fuctionResult == 'Failed' ]]
then
  exit 1
fi

LOCATION=$(echo $fuctionResult | python3 -c "import json,sys;obj=json.load(sys.stdin);print(obj['compute']['location']);")
INSTANCE_ID=$(echo $fuctionResult | python3 -c "import json,sys;obj=json.load(sys.stdin);print(obj['compute']['vmId']);")
LOCAL_IPV4=$(echo $fuctionResult | python3 -c "import json,sys;obj=json.load(sys.stdin);print(obj['network']['interface'][0]['ipv4']['ipAddress'][0]['privateIpAddress']);")
INSTANCE_TYPE=$(echo $fuctionResult | python3 -c "import json,sys;obj=json.load(sys.stdin);print(obj['compute']['vmSize']);")
SUBSCRIPTION_ID=$(echo $fuctionResult | python3 -c "import json,sys;obj=json.load(sys.stdin);print(obj['compute']['subscriptionId']);")

# ================================================== FUNCTIONS ================================================== #

function configDirsAndConfFiles () {
  if [ -d $1 ]
  then
    echo "$1 already exists."
    echo 'Doing nothing and moving on...'   
  else
    echo "Creating dir: $1"
    mkdir -p $1
  fi

  if [ -f $2 ]
  then
    echo "Emptying file: $2"
    echo '' > $2
  else
    echo "Touching/creating file: $2"
    touch $2
  fi

  sleep 3s
}

function installSplunk () {
  echo 'Splunk not installed...'
  echo 'Downloading and installing Splunk...'
  cd /tmp
  # curl -s -O $SPLUNK_DOWNLOAD
  # cd /opt
  if [ -f $INSTALLER ]
  then
    $INSTALL_CMD $INSTALLER #> /dev/null 2>&1
  else
    echo "File $INSTALLER is not present. Something has gone wrong."
    exit 1
  fi
}

function configureConfs () {
  DEP_CONF_PATH="$SPLUNKF_HOME/etc/apps/vtm_deployment_cloud/local"
  SERVER_CONF_PATH="$SPLUNKF_HOME/etc/apps/vtm_deployment_cloud/local"
  #INPUTS_CONF_PATH="$SPLUNKF_HOME/etc/system/local"
  DEP_CONF="$DEP_CONF_PATH/deploymentclient.conf"
  SERVER_CONF="$SERVER_CONF_PATH/server.conf"
  #INPUTS_CONF="$INPUTS_CONF_PATH/inputs.conf"

  configDirsAndConfFiles $DEP_CONF_PATH $DEP_CONF
  configDirsAndConfFiles $SERVER_CONF_PATH $SERVER_CONF
  #configDirsAndConfFiles $INPUTS_CONF_PATH $INPUTS_CONF

  echo '[deployment-client]' > $DEP_CONF
  echo 'disabled = false' >> $DEP_CONF
  #echo "clientName = ${ZONE}:${VPC_ID}:${OWNER_ID}:${INSTANCE_TYPE}" >> $DEP_CONF
  echo 'clientName = vtm_offprem' >> $DEP_CONF
  echo '[target-broker:deploymentServer]' >> $DEP_CONF
  echo 'targetUri = vtm-ds.gelogging.com:443' >> $DEP_CONF
  cat $DEP_CONF
  sleep 1s

  echo '[general]' > $SERVER_CONF
  echo 'pass4SymmKey = o75f6WkGeMc6H0PsTxVQ' >> $SERVER_CONF
  echo '[httpServer]' >> $SERVER_CONF 
  echo 'disableDefaultPort = true' >> $SERVER_CONF
  cat $SERVER_CONF
  sleep 1s

  #echo "host = ${HOSTNAME}:${INSTANCE_ID}:${LOCAL_IPV4}:${ZONE}:${VPC_ID}:${OWNER_ID}" >> $INPUTS_CONF
  #cat $INPUTS_CONF
  #sleep 1s
}

function configureSplunkConfigureService () {
  SYSD='/etc/systemd/system'
  SYSD_FILE='SplunkConfigure.service'
  A_NT='After=network.target'

  # Add Splunk Configure Script and .service
  cp -vf $SCRIPTS/az_splunk_config.sh $SPLUNKF_HOME/bin/splunk_config.sh
  chmod +x $SPLUNKF_HOME/bin/splunk_config.sh

  if [ -f $SYSD/$SYSD_FILE ]
  then
    systemctl disable $SYSD_FILE
    rm -rf $SYSD/$SYSD_FILE
  fi
  cp -vf $SCRIPTS/config/$SYSD_FILE $SYSD/
  sed -i "s|$A_NT|$A_NT $SYSD_FILE|g" $SYSD/SplunkForwarder.service
  chmod 700 $SYSD/$SYSD_FILE
  systemctl daemon-reload
  systemctl enable $SYSD_FILE
}

function getSplunkVersion () {
  echo '--------------------------------------'
  echo 'Currently installed version of Splunk:'
  echo '--------------------------------------'
  $SPLUNKF_HOME/bin/splunk version
  cat $SPLUNKF_HOME/etc/splunk.version

  PKG_FIND=''
  if [ -f "$LSB_REL" ] && [[ $(cat "$LSB_REL" | grep DISTRIB_ID=Ubuntu) ]]
  then
    PKG_FIND='dpkg --list'
  elif [ -f "$RH_REL" ]
  then
    PKG_FIND='rpm -qa'
  fi
  $PKG_FIND | grep -i splunk

  SYSD='/etc/systemd/system'
  echo '---------------------'
  echo 'Service file details:'
  echo '---------------------'
  echo "Contents of dir $SYSD:"
  ls /etc/systemd/system | grep -i splunk
  if [ -f $SYSD/SplunkForwarder.service ]
  then
    echo "Contents of file $SYSD/SplunkForwarder.service:"
    cat $SYSD/SplunkForwarder.service
  else
    echo "File $SYSD/SplunkForwarder.service is missing. Failing."
    exit 1
  fi
  echo '----------------------------------------'
  if [ -f $SYSD/SplunkConfigure.service ]
  then
    echo "Contents of file $SYSD/SplunkConfigure.service:"
    cat $SYSD/SplunkConfigure.service
  else
    echo "File $SYSD/SplunkConfigure.service is missing. Failing."
    exit 1
  fi
}

# ================================================== EXECUTION ================================================== #

echo '*****************************************************************'
echo '* GESOS BUILD PROSIONER: SPLUNK FORWARDER INSTALL AND CONFIGURE *'
echo '*****************************************************************'

if [[ $($INSTALL_CHECK_CMD | grep -i splunk ) ]]
then 
  echo 'Package is already installed....' 
  echo 'Currently installed package and version:' 
  echo "$($INSTALL_CHECK_CMD | grep -i splunk )"
else
  installSplunk

  configureConfs

  chown -R $SPLUNK:$SPLUNK $SPLUNKF_HOME

  $SPLUNK_EXEC start --answer-yes --no-prompt --accept-license 
  # $SPLUNK_EXEC enable boot-start &>/dev/null
  # $SPLUNK_EXEC enable boot-start -user splunk -systemd-managed 1&>/dev/null
  /opt/splunkforwarder/bin/splunk enable boot-start -user splunk --answer-yes --no-prompt --accept-license --gen-and-print-passwd > /dev/nul
fi

echo '(Re)arming Splunk...'

configureSplunkConfigureService
sudo /opt/splunkforwarder/bin/splunk --accept-license --answer-yes

# service splunk restart
$SPLUNK_EXEC restart &>/dev/null
echo 'Splunk has been installed and the service has been restarted.'
cd /opt/splunkforwarder/bin
./splunk restart
echo 'Splunk service has been restarted......'
./splunk status
  
$SPLUNK_EXEC stop
$SPLUNK_EXEC clone-prep-clear-config

systemctl daemon-reload
cd /opt/splunkforwarder/bin
./splunk status
./splunk restart
echo 'Splunk service has been restarted......'

chown -R $SPLUNK:$SPLUNK $SPLUNKF_HOME
chmod -R 750 $SPLUNKF_HOME 

getSplunkVersion
