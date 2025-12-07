#!/bin/bash
# This shell script is made by Chia-Chin Chung <60947091s@gapps.ntnu.edu.tw>

# Function to read motion sensor data
read_motion_sensor() {
    local GPIO_PIN=${1:-17}
    
    # Export GPIO pin
    if [ ! -d /sys/class/gpio/gpio${GPIO_PIN} ]; then
        echo "${GPIO_PIN}" > /sys/class/gpio/export
        sleep 0.1
    fi
    
    # Set as input
    echo "in" > /sys/class/gpio/gpio${GPIO_PIN}/direction
    
    # Read the value
    local value=$(cat /sys/class/gpio/gpio${GPIO_PIN}/value)
    
    echo $value
}

publish_motion_simple() {
    local BROKER=$1
    local TOPIC="pqc-mqtt-sensor/motion-sensor"
    local CLIENT_ID="MotionSensor_pub"
    local GPIO_PIN=${2:-17}
    
    echo "Starting simple motion sensor publishing..."
    echo "Publishing to broker: ${BROKER}"
    echo "Topic: ${TOPIC}"
    echo "Press Ctrl+C to stop"
    echo ""
    
    while true; do
        local sensor_value=$(read_motion_sensor ${GPIO_PIN})
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        if [ "$sensor_value" = "1" ]; then
            local message="MOTION DETECTED at $timestamp"
            echo "$message"
            
            mosquitto_pub -h $BROKER -m "$message" -t $TOPIC -q 0 -i "$CLIENT_ID" -d \
                --tls-version tlsv1.3 --cafile /pqc-mqtt/cert/CA.crt \
                --cert /pqc-mqtt/cert/publisher.crt --key /pqc-mqtt/cert/publisher.key
        fi
        
        sleep 1
    done
}

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

publish_motion_simple "$BROKER_IP" "$GPIO_PIN"