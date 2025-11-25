#!/bin/bash
# This shell script is made by Chia-Chin Chung <60947091s@gapps.ntnu.edu.tw>

read -p "Enter BROKER_IP [localhost]: " BROKER_IP
BROKER_IP=${BROKER_IP:-localhost}

read -p "Enter SUB_IP [localhost]: " SUB_IP
SUB_IP=${SUB_IP:-localhost}

SIG_ALG="falcon1024"
INSTALLDIR="/opt/oqssa"
export LD_LIBRARY_PATH=/opt/oqssa/lib64
export OPENSSL_CONF=/opt/oqssa/ssl/openssl.cnf
export PATH="/usr/local/bin:/usr/local/sbin:${INSTALLDIR}/bin:$PATH"

# generate the new subscriber CSR using pre-set CA.key & cert
openssl req -new -newkey $SIG_ALG -keyout /pqc-mqtt/cert/subscriber.key -out /pqc-mqtt/cert/subscriber.csr -nodes -subj "/O=pqc-mqtt-subscriber/CN=$SUB_IP"

# generate the subscriber cert
openssl x509 -req -in /pqc-mqtt/cert/subscriber.csr -out /pqc-mqtt/cert/subscriber.crt -CA /pqc-mqtt/cert/CA.crt -CAkey /pqc-mqtt/cert/CA.key -CAcreateserial -days 365

# modify file permissions
chmod 777 /pqc-mqtt/cert/*
 
# execute the mosquitto MQTT subscriber
mosquitto_sub -h $BROKER_IP -t pqc-mqtt-sensor/motion-sensor -q 0 -i "Client_sub" -d -v \
--tls-version tlsv1.3 --cafile /pqc-mqtt/cert/CA.crt \
--cert /pqc-mqtt/cert/subscriber.crt --key /pqc-mqtt/cert/subscriber.key
