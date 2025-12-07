#!/bin/bash
# Setup script for motion sensor on Raspberry Pi

echo "=== Motion Sensor Setup ==="

# Install required packages
echo "Installing required packages..."
apt update
apt install -y python3 python3-pip gpiod

# Install Python GPIO library (alternative to sysfs)
pip3 install RPi.GPIO

# Test GPIO access
echo "Testing GPIO access..."
if [ -d /sys/class/gpio ]; then
    echo "GPIO sysfs interface: ✓ Available"
else
    echo "GPIO sysfs interface: ✗ Not available"
    echo "You may need to enable GPIO in raspi-config"
fi

# Show common GPIO pin layout
echo ""
echo "=== Common GPIO Pins for Motion Sensors ==="
echo "GPIO17 = Pin 11 (Common for PIR sensors)"
echo "GPIO27 = Pin 13"
echo "GPIO22 = Pin 15"
echo "GPIO5  = Pin 29"
echo "GPIO6  = Pin 31"
echo ""
echo "VCC (5V) = Pin 2 or 4"
echo "GND      = Pin 6, 9, 14, 20, 25, 30, 34, or 39"
echo ""

# Test specific GPIO pin
read -p "Enter GPIO pin to test [17]: " TEST_PIN
TEST_PIN=${TEST_PIN:-17}

echo "Testing GPIO pin ${TEST_PIN}..."
if [ ! -d /sys/class/gpio/gpio${TEST_PIN} ]; then
    echo "${TEST_PIN}" > /sys/class/gpio/export 2>/dev/null && \
    echo "in" > /sys/class/gpio/gpio${TEST_PIN}/direction 2>/dev/null && \
    echo "GPIO ${TEST_PIN}: ✓ Configured successfully"
else
    echo "GPIO ${TEST_PIN}: Already configured"
fi

# Read current value
if [ -f /sys/class/gpio/gpio${TEST_PIN}/value ]; then
    CURRENT_VALUE=$(cat /sys/class/gpio/gpio${TEST_PIN}/value)
    echo "Current value of GPIO ${TEST_PIN}: $CURRENT_VALUE"
    echo "(0 = no motion, 1 = motion detected)"
else
    echo "Could not read GPIO ${TEST_PIN} value"
fi

# Cleanup
echo "${TEST_PIN}" > /sys/class/gpio/unexport 2>/dev/null || true

echo ""
echo "=== Setup Complete ==="
echo "You can now run publisher-start.sh to publish motion sensor data"