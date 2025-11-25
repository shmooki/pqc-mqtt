#!/bin/bash
# This shell script is made by Chia-Chin Chung <60947091s@gapps.ntnu.edu.tw>

# Copy CA certificate to remote hosts using SCP
# Copy CA certificate to remote hosts using SCP
copy_ca_certificate() {
    local user=$1
    local host=$2
    local remote_path=$3
    local role=$4
    
    if [ -n "$user" ]; then
        echo "=== $role ($user@$host) ==="
        
        # Test SSH connection
        if ssh "$user@$host" "echo 'SSH test successful'" &>/dev/null; then
            echo "SSH key authentication: ✓ Working"
            echo "Copying CA certificate and key..."
            
            # Validate local files exist
            if [ ! -f "/pqc-mqtt/CA.crt" ]; then
                echo "✗ Local CA certificate not found: /pqc-mqtt/CA.crt"
                return 1
            fi
            
            if [ ! -f "/pqc-mqtt/CA.key" ]; then
                echo "✗ Local CA key not found: /pqc-mqtt/CA.key"
                return 1
            fi
            
            # Copy both files to /tmp first
            if scp /pqc-mqtt/CA.crt /pqc-mqtt/CA.key "$user@$host:/tmp/"; then
                echo "✓ Files copied to /tmp/ on remote host"
                
                # Move to final location with proper permissions
                if ssh "$user@$host" "
                    sudo mkdir -p '$remote_path' && \
                    sudo cp /tmp/CA.crt /tmp/CA.key '$remote_path'/ && \
                    sudo chmod 777 '$remote_path'/CA.crt && \
                    sudo chmod 777 '$remote_path'/CA.key && \
                    sudo rm -f /tmp/CA.crt /tmp/CA.key
                "; then
                    echo "✓ CA certificate and key installed successfully to $remote_path/"
                else
                    echo "✗ Failed to move files to final location"
                    echo "  Manual command:"
                    echo "  ssh $user@$host \"sudo mkdir -p '$remote_path' && sudo cp /tmp/CA.crt /tmp/CA.key '$remote_path'/ && sudo chmod 644 '$remote_path'/CA.crt && sudo chmod 600 '$remote_path'/CA.key\""
                    return 1
                fi
            else
                echo "✗ Failed to copy CA files to remote host"
                echo "  Manual command: scp /pqc-mqtt/CA.crt /pqc-mqtt/CA.key $user@$host:/tmp/"
                return 1
            fi

        else
            echo "SSH key authentication: ✗ Not set up"
            echo ""
            echo "MANUAL STEPS REQUIRED for $role:"
            echo "1. Set up SSH key authentication:"
            echo "   ssh-copy-id $user@$host"
            echo ""
            echo "2. Copy CA files manually:"
            echo "   scp /pqc-mqtt/CA.crt /pqc-mqtt/CA.key $user@$host:/tmp/"
            echo "   ssh $user@$host \"sudo mkdir -p '$remote_path' && sudo cp /tmp/CA.crt /tmp/CA.key '$remote_path'/ && sudo chmod 644 '$remote_path'/CA.crt && sudo chmod 600 '$remote_path'/CA.key\""
            echo ""
            echo "The CA files are available at: /pqc-mqtt/CA.crt and /pqc-mqtt/CA.key"
            echo ""
        fi
        echo "----------------------------------------"
    fi
}

SIG_ALG="falcon1024"
INSTALLDIR="/opt/oqssa"
export LD_LIBRARY_PATH=/opt/oqssa/lib64
export OPENSSL_CONF=/opt/oqssa/ssl/openssl.cnf
export PATH="/usr/local/bin:/usr/local/sbin:${INSTALLDIR}/bin:$PATH"

echo "=== OQSSA Configuration ==="
read -p "Enter BROKER_IP [localhost]: " BROKER_IP
BROKER_IP=${BROKER_IP:-localhost}

read -p "Enter PUB_IP [localhost]: " PUB_IP
PUB_IP=${PUB_IP:-localhost}

read -p "Enter SUB_IP [localhost]: " SUB_IP
SUB_IP=${SUB_IP:-localhost}

# Get SCP configuration
echo "=== SCP Configuration for CA Certificate ==="
echo "The CA certificate will be copied to subscriber and publisher hosts."
echo "Leave username blank if you don't want to copy to that host."
echo ""

read -p "Enter SSH username for PUBLISHER ($PUB_IP) [leave blank to skip]: " PUB_USER
read -p "Enter SSH username for SUBSCRIBER ($SUB_IP) [leave blank to skip]: " SUB_USER

# Generate CA key and certificate
echo "Generating CA certificate..."
cd /pqc-mqtt
openssl req -x509 -new -newkey $SIG_ALG -keyout /pqc-mqtt/CA.key -out /pqc-mqtt/CA.crt -nodes -subj "/O=pqc-mqtt-ca" -days 3650

# Copy CA certificate to publisher and subscriber
if [ "$PUB_IP" != "localhost" ] && [ -n "$PUB_USER" ]; then
    copy_ca_certificate "$PUB_USER" "$PUB_IP" "/pqc-mqtt/cert" "publisher"
fi

if [ "$SUB_IP" != "localhost" ] && [ -n "$SUB_USER" ]; then
    copy_ca_certificate "$SUB_USER" "$SUB_IP" "/pqc-mqtt/cert" "subscriber"
fi

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
