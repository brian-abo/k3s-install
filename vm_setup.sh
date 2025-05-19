#!/bin/bash

# Proxmox Template ID
TEMPLATE_ID=200

# VM Base ID
BASE_ID=201

# Network Configuration
IP_BASE="172.16.0."
SUBNET="/22"
GATEWAY="172.16.0.1"

# VM Names
VM_NAMES=("k3s-cp-01" "k3s-cp-02" "k3s-cp-03" "k3s-agent-01" "k3s-agent-02" "k3s-agent-03")

# Starting IP address (last octet of IP)
IP_START=31

# Clone and configure each VM
for i in "${!VM_NAMES[@]}"; do
    VM_ID=$((BASE_ID + i))
    VM_NAME=${VM_NAMES[$i]}
    VM_IP="${IP_BASE}$((IP_START + i))$SUBNET"

    echo "Cloning VM: $VM_NAME (ID: $VM_ID) from template $TEMPLATE_ID..."
    qm clone $TEMPLATE_ID $VM_ID --name $VM_NAME --full true --format qcow2
    
    # Set up Cloud-Init network settings
    qm set $VM_ID --ipconfig0 ip=${VM_IP},gw=${GATEWAY}

    # Start the VM
    qm start $VM_ID

    echo "VM $VM_NAME (ID: $VM_ID) configured with IP: $VM_IP"
done

echo "All VMs have been cloned and configured."
