#!/bin/bash
# This shell script is made by Chia-Chin Chung <60947091s@gapps.ntnu.edu.tw>

read -p "Enter BROKER_IP [localhost]: " BROKER_IP
BROKER_IP=${BROKER_IP:-localhost}

read -p "Enter PUB_IP [localhost]: " PUB_IP
PUB_IP=${PUB_IP:-localhost}

SIG_ALG="falcon1024"
INSTALLDIR="/opt/oqssa"
export LD_LIBRARY_PATH=/opt/oqssa/lib64
export OPENSSL_CONF=/opt/oqssa/ssl/openssl.cnf
export PATH="/usr/local/bin:/usr/local/sbin:${INSTALLDIR}/bin:$PATH"

# generate the new publisher CSR using pre-set CA.key & cert
openssl req -new -newkey $SIG_ALG -keyout /pqc-mqtt/cert/publisher.key -out /pqc-mqtt/cert/publisher.csr -nodes -subj "/O=pqc-mqtt-publisher/CN=$PUB_IP"

# generate the publisher cert
openssl x509 -req -in /pqc-mqtt/cert/publisher.csr -out /pqc-mqtt/cert/publisher.crt -CA /pqc-mqtt/cert/CA.crt -CAkey /pqc-mqtt/cert/CA.key -CAcreateserial -days 365

# modify file permissions
chmod 777 /pqc-mqtt/cert/*

# execute the mosquitto MQTT publisher
mosquitto_pub -h $BROKER_IP -m "Hello world." -t pqc-mqtt-sensor/motion-sensor -q 0 -i "Client_pub" -d --repeat 60 --repeat-delay 1 \
--tls-version tlsv1.3 --cafile /pqc-mqtt/cert/CA.crt \
--cert /pqc-mqtt/cert/publisher.crt --key /pqc-mqtt/cert/publisher.key