#!/bin/bash

# VM IDs to be deleted
VM_IDS=(201 202 203 204 205 206)

echo "Starting VM destruction process..."

for VM_ID in "${VM_IDS[@]}"; do
    echo "Stopping VM $VM_ID..."
    qm stop $VM_ID --skiplock

    echo "Destroying VM $VM_ID..."
    qm destroy $VM_ID --purge

    echo "VM $VM_ID has been destroyed."
done

echo "All specified VMs have been removed."
