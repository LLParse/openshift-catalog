# OpenShift Origin v1.2.1 on Rancher

This template was developed to run Openshift Origin alongside Kubernetes, orchestrated by Rancher. This is advantageous for a number of reasons:

* Push-button installation/uninstallation
* Relaxes RHEL-based OS requirement
* Enables simulataneous usage of Rancher and OpenShift templates
* Inherits value of Rancher scheduler
  * actively monitors health of hosts and containers
  * automatically restores functionality/resiliency without running an Ansible playbook

## Usage

1. Define a custom catalog named **library** pointing to this repository (ADMIN >> Settings)
2. Follow [this wiki](https://github.com/rancher/rancher/wiki/Kubernetes-Management#deployment-types) for your desired Kubernetes deployment type. Port 8443 needs to be opened on all hosts **before** registering them to the environment.
3. OpenShift UI will be accessible on port 8443 (HTTPS). Default username/password is `admin/rancher`