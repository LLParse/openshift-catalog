#!/bin/bash
if [ "$RANCHER_DEBUG" == "true" ]; then set -x; fi

META_URL=http://rancher-metadata.rancher.internal/2015-12-19

oc_gate() {
  oc $@ &> /dev/null
  while [ "$?" != "0" ]; do
    sleep 1
    oc $@ &> /dev/null
  done
}

get_host_addr() {
  addr=$(curl -s ${META_URL}/self/host/agent_ip)
  while [ "$addr" == "" ]; do
    sleep 1
    addr=$(curl -s ${META_URL}/self/host/agent_ip)
  done
  echo $addr
}

get_master_addr() {
  addr=$(curl -s ${META_URL}/services/master/containers/0/primary_ip)
  while [ "$addr" == "" ]; do
    sleep 1
    addr=$(curl -s ${META_URL}/services/master/containers/0/primary_ip)
  done
  echo $addr
}

get_registry_addr() {
  addr=$(oc get svc/docker-registry -o jsonpath='{.spec.clusterIP}')
  while [ "$?" != "0" ]; do
    sleep 1
    addr=$(oc get svc/docker-registry -o jsonpath='{.spec.clusterIP}')
  done
  echo $addr
}

common() {
  CREATE_EXAMPLES=${CREATE_EXAMPLES:-true}
  CREATE_ROUTER=${CREATE_ROUTER:-true}
  CREATE_REGISTRY=${CREATE_REGISTRY:-true}

  HOST_IP=$(get_host_addr)
  HOST_NAME=$(curl -s ${META_URL}/self/host/hostname)
  MASTER_CONFIG=/etc/origin/master
  CA_CERT=${MASTER_CONFIG}/ca.crt
  CA_KEY=${MASTER_CONFIG}/ca.key
  CA_SERIAL=${MASTER_CONFIG}/ca.serial.txt
  ADMIN_CFG=${MASTER_CONFIG}/admin.kubeconfig
  DOCKER_CERTS=/etc/docker/certs.d
}

bootstrap_node() {
  common

  mkdir -p ${MASTER_CONFIG}

  while [ ! -f $CA_CERT ]; do
    UUID=$(curl -s ${META_URL}/services/master/uuid)
    SERVICE_DATA=$(curl -s -u $CATTLE_ACCESS_KEY:$CATTLE_SECRET_KEY "${CATTLE_URL}/services?uuid=${UUID}")
    echo $SERVICE_DATA | jq -r '.data[0].metadata."master.data"' | base64 -d | tar xz
    sleep 1
  done

  # Generate keys and default config
  MASTER_IP=$(get_master_addr)
  oadm create-node-config \
    --dns-ip=${MASTER_IP} \
    --node-client-certificate-authority=${CA_CERT} \
    --certificate-authority=${CA_CERT} \
    --signer-cert=${CA_CERT} \
    --signer-key=${CA_KEY} \
    --signer-serial=${CA_SERIAL} \
    --node-dir=/etc/origin/node \
    --node=${HOST_NAME} \
    --hostnames=${HOST_IP},${HOST_NAME} \
    --master=https://${MASTER_IP}:8443 \
    --volume-dir=/openshift.local.volumes \
    --network-plugin=redhat/openshift-ovs-subnet \
    --config=/etc/origin/node

  configure_node

  openshift start node \
    --config=/etc/origin/node/node-config.yaml \
    --loglevel=2
}

configure_node() {
  # wait for server to open socket
  giddyup probe tcp://${MASTER_IP}:8443 --loop --min 1s --max 16s --backoff 2

  # must exist before registering nodes
  oc_gate get clusternetworks/default

  if [ "$CREATE_REGISTRY" == "true" ]; then
    configure_docker &
  fi
}

configure_docker() {
  destdir_addr=${DOCKER_CERTS}/$(get_registry_addr):5000
  destdir_name=${DOCKER_CERTS}/docker-registry.default.svc.cluster.local:5000

  mkdir -p $destdir_addr $destdir_name
  cp ${CA_CERT} $destdir_addr
  cp ${CA_CERT} $destdir_name
}

if [ $# -eq 0 ]; then
    bootstrap_master
else
    eval $1
fi
