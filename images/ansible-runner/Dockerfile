FROM ansible/ansible:centos7

RUN yum install -y ansible pyOpenSSL

RUN git clone https://github.com/openshift/openshift-ansible -b enterprise-3.2 /openshift-ansible

# TODO (llparse): dynamically generate hosts file
ADD hosts /etc/ansible/hosts
ADD run.sh /