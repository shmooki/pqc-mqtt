#!/bin/bash
# This shell script is made by Chia-Chin Chung <60947091s@gapps.ntnu.edu.tw>

# GPIO pin assignments
# PIR motion sensor: GPIO17 (Physical pin 11)
# LED1 (detection indicator): GPIO20 (Physical pin 38)
# LED2 (status indicator): GPIO21 (Physical pin 40)

# Function to setup GPIO pin
setup_gpio() {
    local GPIO_PIN=$1
    local DIRECTION=$2
    
    # Export GPIO pin if not already exported
    if [ ! -d /sys/class/gpio/gpio${GPIO_PIN} ]; then
        echo "${GPIO_PIN}" > /sys/class/gpio/export
        sleep 0.1
    fi
    
    # Set direction
    echo "${DIRECTION}" > /sys/class/gpio/gpio${GPIO_PIN}/direction
    sleep 0.1
}

# Function to write to GPIO pin
write_gpio() {
    local GPIO_PIN=$1
    local VALUE=$2
    
    # Set as output first
    setup_gpio ${GPIO_PIN} "out"
    
    # Write the value
    echo "${VALUE}" > /sys/class/gpio/gpio${GPIO_PIN}/value
}

# Function to read motion sensor data
read_motion_sensor() {
    local MOTION_GPIO=${1:-14}
    local LED_DETECT_GPIO=${2:-20}
    local LED_STATUS_GPIO=${3:-21}
    
    # Setup GPIO pins
    setup_gpio ${MOTION_GPIO} "in"
    setup_gpio ${LED_DETECT_GPIO} "out"
    setup_gpio ${LED_STATUS_GPIO} "out"
    
    # Turn on status LED (shows script is running)
    write_gpio ${LED_STATUS_GPIO} "1"
    
    # Read the motion sensor value
    local value=$(cat /sys/class/gpio/gpio${MOTION_GPIO}/value)
    
    # If motion detected, blink detection LED
    if [ "$value" = "1" ]; then
        # Blink detection LED
        write_gpio ${LED_DETECT_GPIO} "1"
        sleep 0.5
        write_gpio ${LED_DETECT_GPIO} "0"
    else
        # Ensure detection LED is off
        write_gpio ${LED_DETECT_GPIO} "0"
    fi
    
    echo $value
}

# Function to cleanup GPIO on exit
cleanup_gpio() {
    local GPIO_PINS="17 20 21"
    
    for pin in $GPIO_PINS; do
        if [ -d /sys/class/gpio/gpio${pin} ]; then
            echo "0" > /sys/class/gpio/gpio${pin}/value 2>/dev/null
            echo "${pin}" > /sys/class/gpio/unexport 2>/dev/null
        fi
    done
    echo "GPIO cleanup completed"
}

publish_motion_simple() {
    local BROKER=$1
    local MOTION_GPIO=${2:-17}
    local LED_DETECT_GPIO=${3:-20}
    local LED_STATUS_GPIO=${4:-21}
    
    # Setup cleanup on script exit
    trap cleanup_gpio EXIT INT TERM
    
    echo "Starting PQC Motion Sensor Publishing System"
    echo "============================================="
    echo "Publishing to broker: ${BROKER}"
    echo "Topic: pqc-mqtt-sensor/motion-sensor"
    echo "Motion Sensor GPIO: ${MOTION_GPIO}"
    echo "Detection LED GPIO: ${LED_DETECT_GPIO}"
    echo "Status LED GPIO: ${LED_STATUS_GPIO}"
    echo ""
    echo "System Status:"
    echo "- Status LED (GPIO21): ON (system running)"
    echo "- Detection LED (GPIO20): Will blink on motion"
    echo "- Press Ctrl+C to stop"
    echo "============================================="
    
    # Initialize LEDs
    write_gpio ${LED_STATUS_GPIO} "1"  # Status LED ON
    write_gpio ${LED_DETECT_GPIO} "0"  # Detection LED OFF
    
    local last_motion_time=""
    local motion_count=0
    
    while true; do
        local sensor_value=$(read_motion_sensor ${MOTION_GPIO} ${LED_DETECT_GPIO} ${LED_STATUS_GPIO})
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        if [ "$sensor_value" = "1" ]; then
            motion_count=$((motion_count + 1))
            last_motion_time=$timestamp
            
            local message="{\"timestamp\": \"$timestamp\", \"status\": \"MOTION_DETECTED\", \"count\": $motion_count, \"last_detection\": \"$last_motion_time\"}"
            
            echo "[$timestamp] MOTION DETECTED - Total detections: $motion_count"
            
            # Publish to MQTT broker with PQC certificates
            mosquitto_pub -h $BROKER -m "$message" -t "pqc-mqtt-sensor/motion-sensor" -q 0 -i "MotionSensor_pub" -d \
                --tls-version tlsv1.3 --cafile /pqc-mqtt/cert/CA.crt \
                --cert /pqc-mqtt/cert/publisher.crt --key /pqc-mqtt/cert/publisher.key
            
            # Brief pause after detection to avoid rapid triggers
            sleep 2
        else
            if [ $((motion_count % 10)) -eq 0 ] && [ "$last_motion_time" != "" ]; then
                local status_message="{\"timestamp\": \"$timestamp\", \"status\": \"SYSTEM_ACTIVE\", \"total_detections\": $motion_count, \"last_detection\": \"$last_motion_time\"}"
                echo "[$timestamp] System active - Total detections: $motion_count"
                
                mosquitto_pub -h $BROKER -m "$status_message" -t "pqc-mqtt-sensor/motion-sensor/status" -q 0 -i "MotionSensor_pub" -d \
                    --tls-version tlsv1.3 --cafile /pqc-mqtt/cert/CA.crt \
                    --cert /pqc-mqtt/cert/publisher.crt --key /pqc-mqtt/cert/publisher.key
            fi
        fi
        
        sleep 0.5  # Polling interval
    done
}

# Main execution
echo "PQC Motion Sensor Publisher Setup"
echo "================================="

read -p "Enter BROKER_IP [localhost]: " BROKER_IP
BROKER_IP=${BROKER_IP:-localhost}

read -p "Enter PUB_IP [localhost]: " PUB_IP
PUB_IP=${PUB_IP:-localhost}

SIG_ALG="falcon1024"
INSTALLDIR="/opt/oqssa"
export LD_LIBRARY_PATH=/opt/oqssa/lib64
export OPENSSL_CONF=/opt/oqssa/ssl/openssl.cnf
export PATH="/usr/local/bin:/usr/local/sbin:${INSTALLDIR}/bin:$PATH"

echo "Generating PQC certificates..."
openssl req -new -newkey $SIG_ALG -keyout /pqc-mqtt/cert/publisher.key -out /pqc-mqtt/cert/publisher.csr -nodes -subj "/O=pqc-mqtt-publisher/CN=$PUB_IP"

# generate the publisher cert
openssl x509 -req -in /pqc-mqtt/cert/publisher.csr -out /pqc-mqtt/cert/publisher.crt -CA /pqc-mqtt/cert/CA.crt -CAkey /pqc-mqtt/cert/CA.key -CAcreateserial -days 365

# modify file permissions
chmod 777 /pqc-mqtt/cert/*

echo "Starting motion sensor publisher..."
echo ""

# Start publishing with GPIO configuration
publish_motion_simple "$BROKER_IP" "17" "20" "21"