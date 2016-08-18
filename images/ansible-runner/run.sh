#!/bin/bash -x

META_URL="http://rancher-metadata.rancher.internal/2015-12-19"
DOCKER_VERSION_LABEL=io.rancher.host.docker_version
AUTH_PORT=33518
SSHD_PORT=31381

probe_loop() {
  >/dev/tcp/$1/$2
  while [ "$?" != "0" ]; do
    sleep 1
    >/dev/tcp/$1/$2
  done
}

if [ ! -f ~/.ssh/.generated ]; then
  rm -f ~/.ssh/id_rsa ~./ssh/id_rsa.pub
  ssh-keygen -f ~/.ssh/id_rsa -N ''
  touch ~/.ssh/.generated
fi

# Loop through hosts, wait for services and authorize our public key
for host in $(curl -s ${META_URL}/hosts); do
  id=$(echo $host | cut -d '=' -f 1)

  # TODO (llparse) check for 'openshift' label key
  if [ "$(curl -s ${META_URL}/hosts/${id}/labels/${DOCKER_VERSION_LABEL})" == "1.10" ]; then
    agent_ip=$(curl -s ${META_URL}/hosts/${id}/agent_ip)
    
    probe_loop $agent_ip $AUTH_PORT
    probe_loop $agent_ip $SSHD_PORT

    curl -X POST -d "$(cat /root/.ssh/id_rsa.pub)" ${agent_ip}:${AUTH_PORT}/authorized_keys
    curl -X POST ${agent_ip}:${AUTH_PORT}/shutdown
  fi  
done

# TODO: Loop through hosts and build Ansible hosts file

ansible-playbook /openshift-ansible/playbooks/byo/config.yml

# TODO: un-hodor
sleep 1000000
