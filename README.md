Create the VM's
`ssh -i ~/.ssh/proxmox <user>@<proxmox_ip>'bash -s' < vm_setup.sh`

Build cluster
`./new_install.sh`

Destroy the VM's
`ssh -i ~/.ssh/proxmox <user>@<proxmox_ip>'bash -s' < vm_destroy.sh'`''
