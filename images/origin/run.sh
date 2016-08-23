#!/bin/bash
if [ "$RANCHER_DEBUG" == "true" ]; then set -x; fi

oc_gate() {
  oc $@ &> /dev/null
  while [ "$?" != "0" ]; do
    sleep 1
    oc $@ &> /dev/null
  done
}

common() {
  META_URL=http://rancher-metadata.rancher.internal/2015-12-19
  HOST_IP=$(curl -s ${META_URL}/self/host/agent_ip)
  # sometimes returns empty??
  while [ "$HOST_IP" == "" ]; do
    sleep 1
    HOST_IP=$(curl -s ${META_URL}/self/host/agent_ip)
  done

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
    --etcd=http://etcd.rancher.internal:2379 \
    --master=https://${HOST_IP}:8443 \
    --public-master=https://${HOST_IP}:8443 \
    --cors-allowed-origins=localhost,127.0.0.1,${HOST_IP},${HOST_NAME},origin-master \
    --write-config=${MASTER_CONFIG}

  UUID=$(curl -s ${META_URL}/services/origin-master/uuid)
  SERVICE_DATA=$(curl -s -u $CATTLE_ACCESS_KEY:$CATTLE_SECRET_KEY "${CATTLE_URL}/services?uuid=$UUID")
  PROJECT_ID=$(echo $SERVICE_DATA | jq -r '.data[0].accountId')
  SERVICE_ID=$(echo $SERVICE_DATA | jq -r '.data[0].id')
  SERVICE_DATA=$(curl -s -u $CATTLE_ACCESS_KEY:$CATTLE_SECRET_KEY "${CATTLE_URL}/projects/$PROJECT_ID/services/$SERVICE_ID")
  SERVICE_DATA=$(echo $SERVICE_DATA | jq -r ".metadata |= .+ {\"ca.crt\":\"$(cat $CA_CERT | base64)\"}")
  SERVICE_DATA=$(echo $SERVICE_DATA | jq -r ".metadata |= .+ {\"ca.key\":\"$(cat $CA_KEY | base64)\"}")
  SERVICE_DATA=$(echo $SERVICE_DATA | jq -r ".metadata |= .+ {\"ca.serial\":\"$(cat $CA_SERIAL | base64)\"}")
  SERVICE_DATA=$(echo $SERVICE_DATA | jq -r ".metadata |= .+ {\"admin.kubeconfig\":\"$(cat $ADMIN_CFG | base64)\"}")

  curl -s -X PUT \
    -u "${CATTLE_ACCESS_KEY}:${CATTLE_SECRET_KEY}" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -d "${SERVICE_DATA}" \
    "${CATTLE_URL}/projects/$PROJECT_ID/services/$SERVICE_ID"

  configure &

  # Run master
  openshift start master \
    --config=${MASTER_CONFIG}/master-config.yaml \
    --loglevel=2
}

bootstrap_node() {
  common
  MASTER_IP=$(curl -s rancher-metadata/latest/services/origin-master/containers/0/primary_ip)

  mkdir -p ${MASTER_CONFIG}
  UUID=$(curl -s ${META_URL}/services/origin-master/uuid)
  SERVICE_DATA=$(curl -s -u $CATTLE_ACCESS_KEY:$CATTLE_SECRET_KEY "${CATTLE_URL}/services?uuid=$UUID")
  echo $SERVICE_DATA | jq -r '.data[0].metadata."ca.crt"' | base64 -d > $CA_CERT
  echo $SERVICE_DATA | jq -r '.data[0].metadata."ca.key"' | base64 -d > $CA_KEY
  echo $SERVICE_DATA | jq -r '.data[0].metadata."ca.serial"' | base64 -d > $CA_SERIAL
  echo $SERVICE_DATA | jq -r '.data[0].metadata."admin.kubeconfig"' | base64 -d > $ADMIN_CFG
  # FIXME maybe we need more config?

  # Generate keys and default config
  oadm create-node-config \
    --node-client-certificate-authority=${CA_CERT} \
    --certificate-authority=${CA_CERT} \
    --signer-cert=${CA_CERT} \
    --signer-key=${CA_KEY} \
    --signer-serial=${CA_SERIAL} \
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
  CREATE_EXAMPLES=${CREATE_EXAMPLES:-true}
  CREATE_ROUTER=${CREATE_ROUTER:-true}
  CREATE_REGISTRY=${CREATE_REGISTRY:-true}

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

  REGISTRY_IP=$(oc get svc/docker-registry -o jsonpath='{.spec.clusterIP}')
  while [ "$?" != "0" ]; do
    sleep 1
    REGISTRY_IP=$(oc get svc/docker-registry -o jsonpath='{.spec.clusterIP}')
  done
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

  destdir_addr=${DOCKER_CERTS}/${REGISTRY_IP}:5000
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
