#!/bin/bash

# GPIO configuration for Raspberry Pi 5 with RP1
GPIO_CHIP="gpiochip0"
MOTION_PIN=14
LED_DETECT_PIN=20
LED_STATUS_PIN=21

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

echo ""
echo "Starting motion sensor monitor with persistent MQTT connection..."
echo ""

# Function to publish with persistent connection using a named pipe
setup_mqtt_publisher() {
    # Create a named pipe for MQTT messages
    MQTT_PIPE="/tmp/mqtt_pipe_$$"
    mkfifo "$MQTT_PIPE"
    
    # Start mosquitto_pub in background with persistent connection
    echo "Starting persistent MQTT connection to $BROKER_IP..."
    
    # Remove -d flag to avoid debug output
    mosquitto_pub -h "$BROKER_IP" \
        -t "pqc-mqtt-sensor/motion-sensor" \
        -q 0 \
        -i "MotionSensor_pub" \
        --tls-version tlsv1.3 \
        --cafile /pqc-mqtt/cert/CA.crt \
        --cert /pqc-mqtt/cert/publisher.crt \
        --key /pqc-mqtt/cert/publisher.key \
        -l < "$MQTT_PIPE" &
    
    MQTT_PID=$!
    echo "MQTT publisher PID: $MQTT_PID"
    
    # Return the pipe path
    echo "$MQTT_PIPE"
}

# Function to send message through the pipe
send_mqtt_message() {
    local pipe="$1"
    local message="$2"
    
    if [ -p "$pipe" ]; then
        echo "$message" > "$pipe" &
        return 0
    else
        return 1
    fi
}

# Initialize GPIO
echo "Initial motion sensor reading:"
initial_state=$(sudo gpioget $GPIO_CHIP $MOTION_PIN 2>/dev/null || echo "error")
echo "GPIO$MOTION_PIN = $initial_state"

# Turn on status LED
sudo gpioset $GPIO_CHIP $LED_STATUS_PIN=1
echo "Status LED: ON (GPIO$LED_STATUS_PIN)"

# Setup MQTT publisher with persistent connection
MQTT_PIPE=$(setup_mqtt_publisher)
sleep 2  # Give MQTT client time to connect

echo "Watching for motion on GPIO$MOTION_PIN..."
echo "Press Ctrl+C to stop"
echo "-----------------------------------------"

last_state="0"
first_run=true
LAST_CONNECTION_CHECK=$(date +%s)

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    
    # Kill MQTT publisher
    if [ ! -z "$MQTT_PID" ]; then
        echo "Stopping MQTT publisher (PID: $MQTT_PID)..."
        kill $MQTT_PID 2>/dev/null
        wait $MQTT_PID 2>/dev/null
    fi
    
    # Remove pipe
    if [ -p "$MQTT_PIPE" ]; then
        rm -f "$MQTT_PIPE"
    fi
    
    # Turn off LEDs
    sudo gpioset $GPIO_CHIP $LED_STATUS_PIN=0
    sudo gpioset $GPIO_CHIP $LED_DETECT_PIN=0
    
    echo "✅ Cleanup complete"
    echo "Goodbye!"
    exit 0
}

# Setup trap for cleanup
trap cleanup INT TERM EXIT

while true; do
    # Read motion sensor
    current_state=$(sudo gpioget $GPIO_CHIP $MOTION_PIN 2>/dev/null || echo "error")
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ "$current_state" = "error" ]; then
        echo "[$timestamp] ❌ ERROR: Cannot read GPIO$MOTION_PIN"
        sleep 2
        continue
    fi
    
    # Check MQTT connection every 30 seconds
    current_time=$(date +%s)
    if [ $((current_time - LAST_CONNECTION_CHECK)) -ge 30 ]; then
        heartbeat_msg="{\"timestamp\": \"$timestamp\", \"status\": \"heartbeat\"}"
        if send_mqtt_message "$MQTT_PIPE" "$heartbeat_msg"; then
            echo "[$timestamp]  :   Connection check OK"
        else
            echo "[$timestamp]  :   MQTT pipe issue, attempting to reconnect..."
            cleanup
            # Re-setup MQTT
            MQTT_PIPE=$(setup_mqtt_publisher)
            sleep 2
        fi
        LAST_CONNECTION_CHECK=$current_time
    fi
    
    # Motion detection logic
    if [ "$first_run" = true ] && [ "$current_state" = "1" ]; then
        echo "[$timestamp]  :   Motion detected."
        
        # Blink detection LED
        sudo gpioset $GPIO_CHIP $LED_DETECT_PIN=1
        sleep 0.3
        sudo gpioset $GPIO_CHIP $LED_DETECT_PIN=0
        
        # Publish to MQTT
        message="{\"timestamp\": \"$timestamp\", \"motion\": true, \"type\": \"initial\"}"
        send_mqtt_message "$MQTT_PIPE" "$message"
        
        first_run=false
        last_state="1"
        sleep 2
        
    elif [ "$current_state" = "1" ] && [ "$last_state" = "0" ]; then
        # Rising edge detection
        count=$((count + 1))
        echo "[$timestamp]  : Motion detected"
        
        # Blink detection LED
        sudo gpioset $GPIO_CHIP $LED_DETECT_PIN=1
        sleep 0.3
        sudo gpioset $GPIO_CHIP $LED_DETECT_PIN=0
        
        # Publish to MQTT
        message="{\"timestamp\": \"$timestamp\", \"motion\": true, \"type\": \"detection\"}"
        send_mqtt_message "$MQTT_PIPE" "$message"
        
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
    fi
    
    sleep 0.5  # Polling interval
done