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
  addr=$(curl -s ${META_URL}/services/origin-master/containers/0/primary_ip)
  while [ "$addr" == "" ]; do
    sleep 1
    addr=$(curl -s ${META_URL}/services/origin-master/containers/0/primary_ip)
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

bootstrap_master() {
  common

  # Generate keys and default config
  openshift start master \
    --cors-allowed-origins=localhost,127.0.0.1,${HOST_IP},${HOST_NAME},origin-master \
    --dns=tcp://0.0.0.0:53 \
    --etcd=http://etcd.rancher.internal:2379 \
    --listen=https://0.0.0.0:8443 \
    --master=https://${HOST_IP}:8443 \
    --network-plugin=redhat/openshift-ovs-subnet \
    --public-master=https://${HOST_IP}:8443 \
    --write-config=${MASTER_CONFIG}

  UUID=$(curl -s ${META_URL}/services/origin-master/uuid)
  SERVICE_DATA=$(curl -s -u $CATTLE_ACCESS_KEY:$CATTLE_SECRET_KEY "${CATTLE_URL}/services?uuid=$UUID")
  PROJECT_ID=$(echo $SERVICE_DATA | jq -r '.data[0].accountId')
  SERVICE_ID=$(echo $SERVICE_DATA | jq -r '.data[0].id')
  SERVICE_DATA=$(curl -s -u $CATTLE_ACCESS_KEY:$CATTLE_SECRET_KEY "${CATTLE_URL}/projects/${PROJECT_ID}/services/${SERVICE_ID}")
  SERVICE_DATA=$(echo $SERVICE_DATA | jq -r ".metadata |= .+ {\"master.data\":\"$(tar czf - master | base64)\"}")

  curl -s -X PUT \
    -u "${CATTLE_ACCESS_KEY}:${CATTLE_SECRET_KEY}" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -d "${SERVICE_DATA}" \
    "${CATTLE_URL}/projects/$PROJECT_ID/services/${SERVICE_ID}"

  configure_master &

  # Run master
  openshift start master \
    --config=${MASTER_CONFIG}/master-config.yaml \
    --loglevel=2
}

bootstrap_node() {
  common

  mkdir -p ${MASTER_CONFIG}

  while [ ! -f $CA_CERT ]; do
    UUID=$(curl -s ${META_URL}/services/origin-master/uuid)
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

configure_master() {
  # wait for server to open socket
  giddyup probe tcp://${HOST_IP}:8443 --loop --min 1s --max 16s --backoff 2

  configure_admin
  if [ "$CREATE_EXAMPLES" == "true" ]; then
    create_examples
  fi
  if [ "$CREATE_ROUTER" == "true" ]; then
    create_router
  fi
  if [ "$CREATE_REGISTRY" == "true" ]; then
    create_registry
    configure_docker
  fi
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

configure_admin() {
  # Give admin user the admin role for initial projects
  projects=(default openshift openshift-infra)
  for project in ${projects[@]}; do
    oc_gate get project $project
    oc policy add-role-to-user admin admin -n $project
  done

  #oadm policy add-role-to-user system:image-builder admin
  #oadm policy add-role-to-user system:image-puller admin
  #oadm policy add-role-to-user system:deployer admin
}

create_examples() {
  oc_gate get ns openshift
  oc_gate get project openshift

  cd /examples
  for d in $(ls); do 
    for f in $(ls $d/*.json); do
      oc create -f $f -n openshift
    done
  done
}

create_router() {
  oadm policy add-scc-to-user hostnetwork -z router
  oadm router
}

create_registry() {
  oadm registry \
    --service-account=registry
    #--mount-host=/var/lib/registry

  REGISTRY_IP=$(get_registry_addr)
  giddyup probe tcp://${REGISTRY_IP}:5000 --loop --min 1s --max 16s --backoff 2

  oadm ca create-server-cert \
      --signer-cert=${CA_CERT} \
      --signer-key=${CA_KEY} \
      --signer-serial=${CA_SERIAL} \
      --hostnames="docker-registry.default.svc.cluster.local,${REGISTRY_IP}" \
      --cert=/etc/secrets/registry.crt \
      --key=/etc/secrets/registry.key

  oc secrets new registry-secret \
      /etc/secrets/registry.crt \
      /etc/secrets/registry.key

  oc secrets add registry registry-secret
  oc secrets add default registry-secret

  oc volume dc/docker-registry \
    --add \
    --type=secret \
    --secret-name=registry-secret \
    -m /etc/secrets

  oc env dc/docker-registry \
      REGISTRY_HTTP_TLS_CERTIFICATE=/etc/secrets/registry.crt \
      REGISTRY_HTTP_TLS_KEY=/etc/secrets/registry.key
  
  oc patch dc/docker-registry --api-version=v1 -p '{"spec": {"template": {"spec": {"containers":[{
    "name":"registry",
    "livenessProbe":  {"httpGet": {"scheme":"HTTPS"}}
  }]}}}}'

  oc patch dc/docker-registry --api-version=v1 -p '{"spec": {"template": {"spec": {"containers":[{
    "name":"registry",
    "readinessProbe":  {"httpGet": {"scheme":"HTTPS"}}
  }]}}}}'
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
