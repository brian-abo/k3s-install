k3s-install

Bash Automation for Deploying a 6-Node K3s Cluster on Proxmox
This project provides Bash scripts to automate the provisioning and configuration of a six-node K3s Kubernetes cluster within a Proxmox VE environment. 

It's tailored to streamline the deployment of a lightweight, highly available Kubernetes cluster for home lab use.

🧰 Features

Automated VM Provisioning: Creates six Ubuntu-based virtual machines on Proxmox using cloud-init templates.
K3s Cluster Setup: Installs and configures K3s across the nodes, establishing a functional Kubernetes cluster.
Ingress Configuration: Sets up ingress controllers and configures TLS certificates for secure access.
Customizable Parameters: Allows users to define network settings, VM specifications, and other configurations.

📁 Repository Structure

```k3s-install/
├── install.sh              # Main script to install and configure the K3s cluster
├── vm_setup.sh             # Script to provision VMs on Proxmox
├── vm_destroy.sh           # Script to destroy the provisioned VMs
├── README.md               # Project documentation```

⚙️ Prerequisites
 - Proxmox VE: A running Proxmox server with access to create and manage VMs.
 - Ubuntu Cloud Image: An Ubuntu cloud image template available in Proxmox.
 - SSH Access: Passwordless SSH access set up for the VMs.

🚀 Usage

Clone the Repository:
git clone https://github.com/brian-abo/k3s-install.git
cd k3s-install
Provision VMs:
Use the vm_setup.sh script to create six VMs on your Proxmox server:

`ssh -i ~/.ssh/proxmox <user>@<proxmox_ip> 'bash -s' < vm_setup.sh`
Replace <user> and <proxmox_ip> with your Proxmox credentials.

Install and Configure K3s Cluster:
Run the install.sh script to install K3s on the provisioned VMs and set up the cluster:

`./install.sh`

Destroy VMs (Optional):
If you wish to tear down the cluster, use the vm_destroy.sh script:

`ssh -i ~/.ssh/proxmox <user>@<proxmox_ip> 'bash -s' < vm_destroy.sh`

🔐 Accessing the Cluster

Kubeconfig File: After the cluster is set up, kubeconfig file is retrieved from the control plane and stored as `k3s.yaml`
Move that file to your .kube directory and rename to config or export it's path as KUBECONFIG.

Verify Cluster Access: Use kubectl to interact with your cluster:
  `kubectl get nodes`

