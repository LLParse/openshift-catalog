#!/bin/bash -x

oc_gate() {
  oc $@ &> /dev/null
  while [ "$?" != "0" ]; do
    sleep 1
    oc $@ &> /dev/null
  done
}

common() {
  HOST_IP=$(curl -s http://rancher-metadata/2015-12-19/self/host/agent_ip)
  HOST_NAME=$(curl -s http://rancher-metadata/2015-12-19/self/host/hostname)
}

bootstrap_master() {
  common

  # Generate keys and default config
  openshift start master \
    --etcd=http://etcd:2379 \
    --master=https://${HOST_IP}:8443 \
    --public-master=https://${HOST_IP}:8443 \
    --cors-allowed-origins=localhost,127.0.0.1,${HOST_IP},${HOST_NAME},origin-master \
    --write-config=/etc/origin/master

  configure &

  # Run master
  openshift start master \
    --config=/etc/origin/master/master-config.yaml \
    --loglevel=2
}

bootstrap_node() {
  common
  MASTER_IP=$(curl rancher-metadata/latest/services/origin-master/containers/0/primary_ip)

  # TODO (llparse) make master keys available to nodes
  # Generate keys and default config
  oadm create-node-config \
    --node-client-certificate-authority=/etc/origin/master/ca.crt \
    --certificate-authority=/etc/origin/master/ca.crt \
    --signer-cert=/etc/origin/master/ca.crt \
    --signer-key=/etc/origin/master/ca.key \
    --signer-serial=/etc/origin/master/ca.serial.txt \
    --node-dir=/etc/origin/node \
    --node=${HOST_NAME} \
    --hostnames=${HOST_IP} \
    --master=https://${MASTER_IP}:8443 \
    --config=/etc/origin/node


  openshift start node \
    --config=/etc/origin/node/node-config.yaml \
    --loglevel=2
}

configure() {
  # wait for server to open socket
  giddyup probe tcp://${HOST_IP}:8443 --loop --min 1s --max 16s --backoff 2

  create_examples
  configure_admin
}

create_examples() {
  # wait for openshift project/namespace to exist
  oc_gate get ns openshift
  oc_gate get project openshift

  cd /examples
  for d in $(ls); do 
    for f in $(ls $d/*.json); do
      oc create -f $f -n openshift
    done
  done
}

configure_admin() {
  # Give admin user the admin role for initial projects
  projects=(default openshift openshift-infra)
  for project in ${projects[@]}; do
    oc_gate get project $project
    oc policy add-role-to-user admin admin -n $project
  done

  # Create router and registry 
  oadm policy add-scc-to-user hostnetwork -z router
  oadm router
  oadm registry
}

if [ $# -eq 0 ]; then
    bootstrap_master
else
    eval $1
fi
