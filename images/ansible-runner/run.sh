#!/bin/bash -x

META_URL="http://rancher-metadata.rancher.internal/2015-12-19"
DOCKER_VERSION_LABEL=io.rancher.host.docker_version
PORT=33518

# Loop through hosts and authorize our public key
for host in $(curl -s ${META_URL}/hosts); do
  id=$(echo $host | cut -d '=' -f 1)

  # TODO (llparse) check for 'openshift' label key
  if [ "$(curl -s ${META_URL}/hosts/${id}/labels/${DOCKER_VERSION_LABEL})" == "1.10" ]; then
    agent_ip=$(curl -s ${META_URL}/hosts/${id}/agent_ip)

    >/dev/tcp/${agent_ip}/${PORT}
    while [ "$?" != "0" ]; do
      sleep 1
      >/dev/tcp/${agent_ip}/${PORT}
    done
    
    curl -s -X POST -d "$(cat /root/.ssh/id_rsa.pub)" ${agent_ip}:${PORT}/authorized_keys
    curl -s -X POST ${agent_ip}:${PORT}/shutdown
  fi  
done

# Loop through hosts and build Ansible hosts file
ansible-playbook /openshift-ansible/playbooks/byo/config.yml

# HODOR
sleep 1000000