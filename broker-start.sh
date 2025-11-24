#!/bin/bash
# This shell script is made by Chia-Chin Chung <60947091s@gapps.ntnu.edu.tw>

read -p "Enter BROKER_IP [localhost]: " BROKER_IP
BROKER_IP=${BROKER_IP:-localhost}

SIG_ALG="falcon1024"
INSTALLDIR="/opt/oqssa"
export LD_LIBRARY_PATH=/opt/oqssa/lib64
export OPENSSL_CONF=/opt/oqssa/ssl/openssl.cnf
export PATH="/usr/local/bin:/usr/local/sbin:${INSTALLDIR}/bin:$PATH"

# generate the configuration file for mosquitto
echo -e "
## Listeners
listener 8883
max_connections -1
max_qos 2
protocol mqtt

## General configuration
allow_anonymous false

## Certificate based SSL/TLS support
cafile /pqc-mqtt/cert/CA.crt
keyfile /pqc-mqtt/cert/broker.key
certfile /pqc-mqtt/cert/broker.crt
tls_version tlsv1.3
ciphers_tls1.3 TLS_AES_128_GCM_SHA256

# Comment out the following two lines if using one-way authentication
require_certificate true

## Same as above
use_identity_as_username true
" > mosquitto.conf

# generate the password file(add username and password) for the mosquitto MQTT broker
mosquitto_passwd -b -c passwd nana 1234

# generate the Access Control List
echo -e "user nana\ntopic readwrite pqc-mqtt-sensor/motion-sensor" > acl

mkdir /pqc-mqtt/cert

# copy the CA key and the cert to the cert folder
cp /pqc-mqtt/CA.key /pqc-mqtt/CA.crt /pqc-mqtt/cert

# generate the new server CSR using pre-set CA.key & cert
openssl req -new -newkey $SIG_ALG -keyout /pqc-mqtt/cert/broker.key -out /pqc-mqtt/cert/broker.csr -nodes -subj "/O=pqc-mqtt-broker/CN=$BROKER_IP"

# generate the server cert
openssl x509 -req -in /pqc-mqtt/cert/broker.csr -out /pqc-mqtt/cert/broker.crt -CA /pqc-mqtt/cert/CA.crt -CAkey /pqc-mqtt/cert/CA.key -CAcreateserial -days 365

# modify file permissions
chmod 777 /pqc-mqtt/cert/*

# execute the mosquitto MQTT broker
mosquitto -c mosquitto.conf -v