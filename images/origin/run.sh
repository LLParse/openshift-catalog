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
  MASTER_CONFIG=/etc/origin/master
  MASTER_CERT=${MASTER_CONFIG}/ca.crt
  MASTER_KEY=${MASTER_CONFIG}/ca.key
  MASTER_SERIAL=${MASTER_CONFIG}/ca.serial.txt
  DOCKER_CERTS=/etc/docker/certs.d
}

bootstrap_master() {
  common

  # Generate keys and default config
  openshift start master \
    --etcd=http://etcd:2379 \
    --master=https://${HOST_IP}:8443 \
    --public-master=https://${HOST_IP}:8443 \
    --cors-allowed-origins=localhost,127.0.0.1,${HOST_IP},${HOST_NAME},origin-master \
    --write-config=${MASTER_CONFIG}

  configure &

  # Run master
  openshift start master \
    --config=${MASTER_CONFIG}/master-config.yaml \
    --loglevel=2
}

bootstrap_node() {
  common
  MASTER_IP=$(curl rancher-metadata/latest/services/origin-master/containers/0/primary_ip)

  # TODO (llparse) make master keys available to nodes
  # Generate keys and default config
  oadm create-node-config \
    --node-client-certificate-authority=${MASTER_CERT} \
    --certificate-authority=${MASTER_CERT} \
    --signer-cert=${MASTER_CERT} \
    --signer-key=${MASTER_KEY} \
    --signer-serial=${MASTER_SERIAL} \
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
  create_router
  create_registry
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

configure_admin() {
  # Give admin user the admin role for initial projects
  projects=(default openshift openshift-infra)
  for project in ${projects[@]}; do
    oc_gate get project $project
    oc policy add-role-to-user admin admin -n $project
  done

  #oadm add-role-to-user system:image-builder admin
  #oadm add-role-to-user system:image-puller admin
  #oadm add-role-to-user system:deployer admin
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
      --signer-cert=${MASTER_CERT} \
      --signer-key=${MASTER_KEY} \
      --signer-serial=${MASTER_SERIAL} \
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
  cp ${MASTER_CERT} $destdir_addr
  cp ${MASTER_CERT} $destdir_name
}

if [ $# -eq 0 ]; then
    bootstrap_master
else
    eval $1
fi
