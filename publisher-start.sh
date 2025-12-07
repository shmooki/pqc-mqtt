#!/bin/bash

cleanup() {
    echo ""
    echo "Cleaning up..."
    sudo gpioset $GPIO_CHIP $LED_STATUS_PIN=0
    sudo gpioset $GPIO_CHIP $LED_DETECT_PIN=0
    echo "GPIO cleaned up"
    exit 0
}

# GPIO configuration for Raspberry Pi 5 with RP1
GPIO_CHIP="gpiochip0"  # RP1 chip on Pi 5
MOTION_PIN=14          # BCM14 - Physical pin 8
LED_DETECT_PIN=20      # BCM20 - Physical pin 38
LED_STATUS_PIN=21      # BCM21 - Physical pin 40

# Broker configuration
read -p "Enter BROKER_IP [localhost]: " BROKER_IP
BROKER_IP=${BROKER_IP:-localhost}

read -p "Enter PUB_IP [localhost]: " PUB_IP
PUB_IP=${PUB_IP:-localhost}

# PQC setup
SIG_ALG="falcon1024"
INSTALLDIR="/opt/oqssa"
export LD_LIBRARY_PATH=/opt/oqssa/lib64
export OPENSSL_CONF=/opt/oqssa/ssl/openssl.cnf
export PATH="/usr/local/bin:/usr/local/sbin:${INSTALLDIR}/bin:$PATH"

echo ""
echo "Generating PQC certificates..."
openssl req -new -newkey $SIG_ALG -keyout /pqc-mqtt/cert/publisher.key -out /pqc-mqtt/cert/publisher.csr -nodes -subj "/O=pqc-mqtt-publisher/CN=$PUB_IP" 2>/dev/null
openssl x509 -req -in /pqc-mqtt/cert/publisher.csr -out /pqc-mqtt/cert/publisher.crt -CA /pqc-mqtt/cert/CA.crt -CAkey /pqc-mqtt/cert/CA.key -CAcreateserial -days 365 2>/dev/null
chmod 777 /pqc-mqtt/cert/* 2>/dev/null || true

echo "Certificates generated successfully."
echo ""

echo "Starting motion sensor monitor..."
echo ""

# Initial motion sensor state
echo "Initial motion sensor reading:"
initial_state=$(sudo gpioget $GPIO_CHIP $MOTION_PIN)
echo "GPIO$MOTION_PIN = $initial_state"
echo ""

# Turn on status LED
sudo gpioset $GPIO_CHIP $LED_STATUS_PIN=1
echo "Status LED: ON (GPIO$LED_STATUS_PIN)"
echo "Watching for motion on GPIO$MOTION_PIN..."
echo "Press Ctrl+C to stop"
echo "-----------------------------------------"

last_state="0"
first_run=true

# Setup trap for cleanup
trap cleanup INT TERM EXIT

while true; do
    # Read motion sensor
    current_state=$(sudo gpioget $GPIO_CHIP $MOTION_PIN 2>/dev/null || echo "error")
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ "$current_state" = "error" ]; then
        echo "[$timestamp] ERROR: Cannot read GPIO$MOTION_PIN"
        sleep 2
        continue
    fi
    
    if [ "$first_run" = true ] && [ "$current_state" = "1" ]; then
        # First run and motion is already detected
        count=$((count + 1))
        echo "[$timestamp]  :   Motion detected"
        
        # Blink detection LED
        sudo gpioset $GPIO_CHIP $LED_DETECT_PIN=1
        sleep 0.3
        sudo gpioset $GPIO_CHIP $LED_DETECT_PIN=0
        
        # Publish to MQTT
        message="{\"timestamp\": \"$timestamp\", \"motion\": true, \"type\": \"initial\"}"
        mosquitto_pub -h $BROKER_IP -m "$message" -t "pqc-mqtt-sensor/motion-sensor" -q 0 -i "MotionSensor_pub" \
            --tls-version tlsv1.3 --cafile /pqc-mqtt/cert/CA.crt \
            --cert /pqc-mqtt/cert/publisher.crt --key /pqc-mqtt/cert/publisher.key 2>/dev/null && \
            echo "Published to MQTT"
        
        first_run=false
        last_state="1"
        sleep 2
        
    elif [ "$current_state" = "1" ] && [ "$last_state" = "0" ]; then
        # Rising edge detection
        count=$((count + 1))
        echo "[$timestamp]  :   Motion detected."
        
        # Blink detection LED
        sudo gpioset $GPIO_CHIP $LED_DETECT_PIN=1
        sleep 0.3
        sudo gpioset $GPIO_CHIP $LED_DETECT_PIN=0
        
        # Publish to MQTT
        message="{\"timestamp\": \"$timestamp\", \"motion\": true, \"type\": \"detection\"}"
        if mosquitto_pub -h $BROKER_IP -m "$message" -t "pqc-mqtt-sensor/motion-sensor" -q 0 -i "MotionSensor_pub" \
            --tls-version tlsv1.3 --cafile /pqc-mqtt/cert/CA.crt \
            --cert /pqc-mqtt/cert/publisher.crt --key /pqc-mqtt/cert/publisher.key 2>/dev/null; then
            echo "Published to MQTT"
        else
            echo "Failed to publish to MQTT"
        fi
        
        last_state="1"
        sleep 2  # Cooldown period
        
    elif [ "$current_state" = "0" ] && [ "$last_state" = "1" ]; then
        # Falling edge - motion stopped
        echo "[$timestamp]  :   Motion cleared"
        last_state="0"
        first_run=false
        
    elif [ "$current_state" = "0" ]; then
        # No motion
        if [ "$first_run" = true ]; then
            first_run=false
        fi
        last_state="0"
        
    elif [ "$current_state" = "1" ] && [ "$last_state" = "1" ]; then
        # Continuous motion - do nothing (already reported)
        :
    fi
    
    # Publish heartbeat every 60 seconds
    current_time=$(date +%s)
    if [ -z "$last_heartbeat" ] || [ $((current_time - last_heartbeat)) -ge 60 ]; then
        heartbeat_msg="{\"timestamp\": \"$timestamp\", \"status\": \"active\", \"sensor_pin\": $MOTION_PIN}"
        echo "[$timestamp]  :   sensor heartbeat"
        
        mosquitto_pub -h $BROKER_IP -m "$heartbeat_msg" -t "pqc-mqtt-sensor/status" -q 0 -i "MotionSensor_pub" \
            --tls-version tlsv1.3 --cafile /pqc-mqtt/cert/CA.crt \
            --cert /pqc-mqtt/cert/publisher.crt --key /pqc-mqtt/cert/publisher.key 2>/dev/null
        
        last_heartbeat=$current_time
    fi
    
    sleep 0.5  
done