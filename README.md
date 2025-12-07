# PQC MQTT Motion Sensor System

A Post-Quantum Cryptography (PQC) secured MQTT motion sensor system with Raspberry Pi GPIO integration. This system enables secure transmission of motion sensor data using quantum-resistant cryptographic algorithms. More specifically, it utilizes the falcon1024 signing algorithm for all MQTT communications.

This repo expands upon the work found here: https://github.com/open-quantum-safe/oqs-demos/tree/main/mosquitto.

Rather than implementing a simple MQTT test with the pre-built Docker file, this repo successfully implements a motion detection system via heavily modified versions of the provided bash scripts. 

## Background

This repository implements a secure IoT motion sensor system using:
- **Post-Quantum Cryptography (PQC)**: Uses Falcon-1024 signatures for quantum-resistant authentication
- **MQTT Protocol**: Lightweight publish-subscribe messaging for IoT communication
- **Raspberry Pi GPIO**: Interfaces with motion sensors and status LEDs
- **TLS 1.3**: Secure communication with PQC cipher suites

The system consists of three main components:
1. **Broker**: MQTT broker with PQC authentication
2. **Publisher**: Motion sensor node that detects and publishes motion events
3. **Subscriber**: Client that receives and displays motion notifications

All three connect via PQC certificates to one another. 

## Prerequisites
You must have the following at your disposal to fully setup the PQC MQTT motion detection system:
- 3 Raspberry Pi 5's
- A breadboard
- An HC-SR501 PIR motion sensor
- 3 female-female jumper wires
- 3 female-male jumper wires
- 2 220 or 300 ohm resistors
- 2 LEDs

You must have SSH configured on each Raspberry Pi as well as its respective local IP address.

## Setup

### 1. Environment Preparation

Run the main setup script to install all dependencies and build the PQC-enabled components:

```bash
chmod +x pqc-mqtt-env-setup.sh && \
sudo ./pqc-mqtt-env-setup.sh
```

This script will:
- Install system dependencies (build tools, libraries, gpiod)
- Download and build liboqs (Open Quantum Safe library)
- Build OpenSSL 3.4.0 with PQC support
- Install oqs-provider for PQC algorithms
- Build and install Mosquitto MQTT broker
- Set up environment variables and library paths
- Create the /pqc-mqtt directory for the implementation architecture

After that, setup the motion detection system circuit the same as below: 
<img width="650" height="523" alt="image" src="https://github.com/user-attachments/assets/58192b06-5e54-4f2a-8e36-020e1fc291fa" />

*Source: https://opensource.com/article/20/11/motion-detection-raspberry-pi*

### 2. Certificate Authority (CA) and Broker Setup

Start the broker to generate CA certificates and configure the MQTT server:
```bash
chmod +x broker-start.sh && \
sudo ./broker-start.sh
```

When prompted, provide:
- Broker IP address: IP where the broker will run
- Publisher IP address: IP of the motion sensor device
- Subscriber IP address: IP of the client receiving notifications
- SSH usernames: For copying CA certificates to publisher/subscriber

The script will:
- Generate CA key and certificate using Falcon-1024
- Copy the CA certificate and key to publisher and subscriber nodes
- Generate the broker certificate
- Create the Mosquitto configuration file with PQC TLS settings
- Set up authentication (username/password and certificate-based)
- Start the Mosquitto broker on port 8883

### 3. Publisher (Motion Sensor) Setup

On the Raspberry Pi with the motion sensor connected:
```bash
chmod +x publisher-start.sh && \
sudo ./publisher-start.sh
```

When prompted, provide:
- Broker IP address: IP of the MQTT broker
- Publisher IP address: Local IP of this device

Hardware Configuration (default):
- Motion Sensor: GPIO14 (BCM14, Physical pin 8)
- Status LED: GPIO21 (BCM21, Physical pin 40)
- Detection LED: GPIO20 (BCM20, Physical pin 38)

Note that these configurations are based on the ones described in section 1. If any pins are changed, then the script will fail to recognize the sensor.

The publisher will:
- Generate its PQC certificate using the CA
- Initialize GPIO pins for motion sensor and LEDs
- Monitor for motion detection
- Publish motion events to the pqc-mqtt-sensor/motion-sensor topic
- Send heartbeat messages every 60 seconds to pqc-mqtt-sensor/status

### 4. Subscriber Setup

On the client device that should receive the motion notifications:
```bash
chmod +x subscriber-start.sh && \
sudo ./subscriber-start.sh
```

When prompted, provide:
- Broker IP address: IP of the MQTT broker
- Subscriber IP address: Local IP of this device

The subscriber will:
- Generate its PQC certificate using the CA
- Connect to the broker with PQC-secured TLS 1.3
- Subscribe to the motion sensor topic
- Display real-time motion notifications

## Cleanup
To completely remove the PQC/MQTT installation and clean up all files:
```bash
chmod +x pqc-mqtt-env-cleanup.sh && \
sudo ./pqc-mqtt-env-cleanup.sh
```

This script will:
- Remove all installation directories (/opt/oqs-*, /opt/liboqs, /opt/openssl, /opt/oqssa, /opt/mosquitto)
- Remove the project directory (/pqc-mqtt)
- Remove Mosquitto binaries and libraries
- Clean up symbolic links

**Warning: This cleanup is irreversible and will remove all certificates and configuration files.**

## Script Details
### pqc-mqtt-env-setup.sh
Main installation script that builds all PQC components from source.

### broker-start.sh
Broker initialization script that generates CA certificates, configures Mosquitto, and starts the broker.

### publisher-start.sh
Motion sensor publisher with GPIO integration for real-time motion detection.

### subscriber-start.sh
MQTT subscriber client for receiving motion notifications.

### pqc-mqtt-env-cleanup.sh
Complete cleanup script for removing all PQC/MQTT components.

## Security Features

- PQC Algorithms: Falcon-1024 for signatures, ML-KEM for key exchange
- Mutual TLS Authentication: Both client and server authentication
- TLS 1.3 Only: Modern protocol with forward secrecy
- Certificate-based Authentication: No anonymous connections
- Access Control: MQTT topic-based ACLs

## Troubleshooting

- GPIO Errors: Ensure gpiod is installed and user has GPIO permissions
- Certificate Errors: Verify CA certificates are correctly copied to all nodes
- Connection Issues: Check firewall settings for port 8883
- Library Errors: Run ldconfig after installation

## Files and Directories

- **/opt/oqssa/** - Main PQC installation directory
- **/pqc-mqtt/** - Test files and certificates
- **/pqc-mqtt/cert/** - CA and device certificates
- **/usr/local/bin/mosquitto** - MQTT binaries




