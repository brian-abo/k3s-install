#!/bin/bash

set -e  # Exit on error

# Define variables
SSH_USER="${SSH_USER:-ubuntu}"  
VIP="172.16.0.30"
INTERFACE="eth0"
KUBE_VIP_VERSION="v0.6.0"
CONTROL_PLANE_NODES=("172.16.0.31" "172.16.0.32" "172.16.0.33")
AGENT_NODES=("172.16.0.34" "172.16.0.35" "172.16.0.36")
ALL_NODES=("${CONTROL_PLANE_NODES[@]}" "${AGENT_NODES[@]}")
TOKEN_FILE=".node-token"

# Function to print banners
print_banner() {
    echo -e "\n====================================="
    echo -e " $1 "
    echo -e "=====================================\n"
}

# Function to configure each remote node
prepare_node() {
    local NODE=$1
    print_banner "🛠️ Preparing Node ${NODE}"
    
    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${NODE} <<EOF || { echo "❌ SSH Connection Failed to ${NODE}"; exit 1; }
        # Install UFW only if it's missing
        if ! dpkg -l | grep -q ufw; then
            sudo apt-get install -y ufw
        fi

        # Add UFW rules only if they are missing
        sudo ufw status | grep -q "6443/tcp" || sudo ufw allow 6443/tcp  # API server
        sudo ufw status | grep -q "10250/tcp" || sudo ufw allow 10250/tcp  # Metrics
        sudo ufw status | grep -q "10.42.0.0/16" || sudo ufw allow from 10.42.0.0/16 to any  # Pods
        sudo ufw status | grep -q "10.43.0.0/16" || sudo ufw allow from 10.43.0.0/16 to any  # Services
        sudo ufw status | grep -q "2379/tcp" || sudo ufw allow 2379/tcp  # etcd
        sudo ufw status | grep -q "2380/tcp" || sudo ufw allow 2380/tcp  # etcd
        sudo ufw status | grep -q "22/tcp" || sudo ufw allow 22/tcp  # SSH
        sudo ufw status | grep -q "8472/udp" || sudo ufw allow 8472/udp
        sudo ufw status | grep -q "53/tcp" || sudo ufw allow 53/tcp
        sudo ufw status | grep -q "53/udp" || sudo ufw allow 53/udp

        echo "y" | sudo ufw enable
        sudo ufw reload

        # Disable swap only if enabled
        if [ "\$(swapon --show | wc -l)" -gt 0 ]; then
            sudo swapoff -a
            sudo sed -i.bak '/swap/s/^/#/' /etc/fstab
        fi

        # Ensure time is synced
        sudo systemctl restart systemd-timesyncd
        sudo timedatectl set-ntp off
        sudo timedatectl set-ntp on

        # Ensure IP forwarding is set correctly without duplicates
        sudo sed -i '/^net.ipv4.ip_forward = 1$/d' /etc/sysctl.conf
        echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
        sudo sysctl -p
EOF

    print_banner "✅ Node ${NODE} Prepared"
}

# Function to setup kube-vip on the first control plane node
setup_kube_vip() {
    print_banner "🚀 Setting Up Kube-VIP on ${CONTROL_PLANE_NODES[0]}"
    
    ssh ${SSH_USER}@${CONTROL_PLANE_NODES[0]} <<EOF
        # Ensure the manifests directory exists
        sudo mkdir -p /var/lib/rancher/k3s/server/manifests

        # Create the kube-vip ServiceAccount and RBAC configuration
        cat <<EOT | sudo tee /var/lib/rancher/k3s/server/manifests/kube-vip-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube-vip
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kube-vip-role
rules:
  - apiGroups: [""]
    resources: ["services", "endpoints"]
    verbs: ["get", "list", "watch", "update", "create", "patch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["get", "list", "watch", "update", "create", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-vip-rolebinding
subjects:
  - kind: ServiceAccount
    name: kube-vip
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: kube-vip-role
  apiGroup: rbac.authorization.k8s.io
EOT

        # Create the kube-vip DaemonSet manifest
        cat <<EOT | sudo tee /var/lib/rancher/k3s/server/manifests/kube-vip.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kube-vip
  namespace: kube-system
  labels:
    app: kube-vip
spec:
  selector:
    matchLabels:
      app: kube-vip
  template:
    metadata:
      labels:
        app: kube-vip
    spec:
      serviceAccountName: kube-vip
      tolerations:
      - key: "node-role.kubernetes.io/control-plane"
        operator: "Exists"
        effect: "NoSchedule"
      - key: "CriticalAddonsOnly"
        operator: "Exists"
        effect: "NoExecute"
      containers:
      - name: kube-vip
        image: ghcr.io/kube-vip/kube-vip:${KUBE_VIP_VERSION}
        imagePullPolicy: IfNotPresent
        args:
        - manager
        env:
        - name: vip_arp
          value: "true"
        - name: address
          value: "${VIP}"
        - name: interface
          value: "${INTERFACE}"
        - name: cp_enable
          value: "true"
        - name: vip_leaderelection
          value: "true"
        securityContext:
          capabilities:
            add:
            - NET_ADMIN
            - NET_RAW
      hostNetwork: true
EOT
EOF

    print_banner "✅ Kube-VIP DaemonSet Configured"
}

# Function to install K3s on the first control plane node
install_first_control_plane() {
    print_banner "🏗️ Installing First Control Plane Node on ${CONTROL_PLANE_NODES[0]}"
    ssh ${SSH_USER}@${CONTROL_PLANE_NODES[0]} <<EOF
        curl -sfL https://get.k3s.io | sh -s - server \
            --cluster-init \
            --node-name=${CONTROL_PLANE_NODES[0]} \
            --tls-san=${VIP} \
            --cluster-cidr=10.42.0.0/16 \
            --service-cidr=10.43.0.0/16 \
            --disable-cloud-controller \
            --node-taint CriticalAddonsOnly=true:NoExecute
EOF
    print_banner "✅ First Control Plane Installed"
}

# Function to install additional control plane nodes
install_control_plane_nodes() {
    print_banner "🔗 Joining Additional Control Plane Nodes"

    TOKEN="$(cat ${TOKEN_FILE})"

    for NODE in "${CONTROL_PLANE_NODES[@]:1}"; do
        print_banner "🔄 Installing Control Plane Node on ${NODE}..."
        
        ssh ${SSH_USER}@${NODE} <<EOF
            echo "🚀 Starting K3s Control Plane Installation on ${NODE}"
            curl -sfL https://get.k3s.io | sh -s - server \
                --server https://${VIP}:6443 \
                --token=${TOKEN} \
                --node-name=${NODE} \
                --disable-cloud-controller \
                --node-taint CriticalAddonsOnly=true:NoExecute
            
            # Check if K3s server started successfully
            if systemctl is-active --quiet k3s; then
                echo "✅ K3s Control Plane Successfully Started on ${NODE}"
            else
                echo "❌ K3s Control Plane Failed on ${NODE}" >&2
                exit 1
            fi
EOF

        # Capture exit status and log appropriately
        if [ $? -eq 0 ]; then
            print_banner "✅ Control Plane Node ${NODE} Joined Successfully!"
        else
            print_banner "❌ ERROR: Control Plane Node ${NODE} Failed to Join!"
            exit 1
        fi
    done
}


# Function to install agent nodes with a role
install_agent_nodes() {
    print_banner "🖥️ Installing K3s Agent Nodes"

    TOKEN="$(cat ${TOKEN_FILE})"

    for NODE in "${AGENT_NODES[@]}"; do
        print_banner "🔄 Installing K3s Agent on ${NODE}..."
        
        ssh ${SSH_USER}@${NODE} <<EOF
            echo "🚀 Starting K3s Agent Installation on ${NODE}"
            curl -sfL https://get.k3s.io | sh -s - agent \
                --server https://${VIP}:6443 \
                --token=${TOKEN} \
                --node-name=${NODE} \
                --node-label "node.kubernetes.io/role=agent"
            
            # Check if K3s agent started successfully
            if systemctl is-active --quiet k3s-agent; then
                echo "✅ K3s Agent Successfully Started on ${NODE}"
            else
                echo "❌ K3s Agent Failed on ${NODE}" >&2
                exit 1
            fi
EOF

        # Capture exit status and log appropriately
        if [ $? -eq 0 ]; then
            print_banner "✅ Agent Node ${NODE} Joined Successfully!"
        else
            print_banner "❌ ERROR: Agent Node ${NODE} Failed to Join!"
            exit 1
        fi
    done
}

# Function to ensure K3s is running post installation
wait_for_k3s() {
    local NODE=$1
    print_banner "⏳ Waiting for K3s to be Ready on ${NODE}"

    ssh ${SSH_USER}@${NODE} <<EOF
        while ! sudo k3s kubectl get nodes >/dev/null 2>&1; do
            echo "⏳ K3s is not ready yet on ${NODE}, waiting..."
            sleep 5
        done
EOF

    print_banner "✅ K3s is Ready on ${NODE}"
}

# Function to ensure the VIP is ready before proceeding
wait_for_vip() {
    print_banner "⏳ Waiting for VIP (${VIP}) to be Ready..."

    # Loop until the VIP responds to ping
    while ! ping -c 1 -W 1 ${VIP} >/dev/null 2>&1; do
        echo "⏳ VIP ${VIP} is not ready yet, waiting..."
        sleep 5
    done

    print_banner "✅ VIP ${VIP} is Now Reachable!"
}


# Function to retrieve and copy K3s token
retrieve_k3s_token() {
    print_banner "🔑 Retrieving K3s Token"

    ssh ${SSH_USER}@${CONTROL_PLANE_NODES[0]} <<EOF
        sudo cp /var/lib/rancher/k3s/server/node-token /tmp/node-token
        sudo chmod 644 /tmp/node-token
EOF

    scp ${SSH_USER}@${CONTROL_PLANE_NODES[0]}:/tmp/node-token ./${TOKEN_FILE}
    ssh ${SSH_USER}@${CONTROL_PLANE_NODES[0]} "sudo rm /tmp/node-token"

    print_banner "✅ K3s Token Retrieved"
}

# Function to setup local kubeconfig
setup_kubeconfig() {
    print_banner "📥 Setting Up Local Kubeconfig"
    for NODE in "${CONTROL_PLANE_NODES[@]}"; do
        if ssh ${SSH_USER}@${NODE} "sudo cat /etc/rancher/k3s/k3s.yaml" | tee k3s.yaml >/dev/null 2>&1; then
            sed -i "s/127.0.0.1/${VIP}/" k3s.yaml
            
            print_banner "✅ Kubeconfig retrieved from ${NODE} and updated"
            break
        else
            echo "❌ Failed to retrieve kubeconfig from ${NODE}, trying next..."
        fi
    done
}

# ** Main Execution Flow **
print_banner "🌍 Preparing All Nodes"
for NODE in "${ALL_NODES[@]}"; do
    prepare_node "$NODE"
done

# install_first_control_plane
wait_for_k3s "${CONTROL_PLANE_NODES[0]}"  # Ensure K3s is fully ready
setup_kube_vip
wait_for_vip  # Ensure VIP is ready before joining more nodes
retrieve_k3s_token
install_control_plane_nodes
install_agent_nodes
setup_kubeconfig

print_banner "🎉 K3s HA Cluster Setup Completed Successfully!"
