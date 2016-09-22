#!/usr/bin/env python

import yaml

path = '/etc/origin/master/master-config.yaml'

config = yaml.load(file(path, 'r'))

# etcd storage paths
config['etcdStorageConfig'] = {
  "kubernetesStoragePrefix": "registry",
  "kubernetesStorageVersion": "v1",
  "openShiftStoragePrefix": "openshift.io",
  "openShiftStorageVersion": "v1"
}

# k8s service account authentication
config['serviceAccountConfig']['privateKeyFile'] = "/etc/kubernetes/ssl/key.pem"
config['serviceAccountConfig']['publicKeyFiles'] = ["/etc/kubernetes/ssl/cert.pem"]

# configure kubelet access to allow tailing sti-build log files
config['kubeletClientInfo'] = {
  "ca": "/etc/kubernetes/ssl/ca.pem",
  "certFile": "/etc/kubernetes/ssl/cert.pem",
  "keyFile": "/etc/kubernetes/ssl/key.pem",
  "port": 10250
}

# user authentication
config['oauthConfig']['identityProviders'][0] = {
  "name": "rancher",
  "challenge": True,
  "login": True,
  "provider": {
    "apiVersion": "v1",
    "kind": "HTPasswdPasswordIdentityProvider",
    "file": "/users.htpasswd"
  }
}

yaml.dump(config, file(path, 'w'), default_flow_style=False)
