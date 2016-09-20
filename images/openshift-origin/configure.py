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
config['serviceAccountConfig'] = {
  "managedNames": ["builder", "deployer"],
  "masterCA": "/etc/kubernetes/ssl/ca.pem",
  "privateKeyFile": "/etc/kubernetes/ssl/key.pem",
  "publicKeyFiles": ["/etc/kubernetes/ssl/cert.pem"]
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
