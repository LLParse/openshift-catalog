FROM ansible/ansible:centos7

RUN yum install -y ansible pyOpenSSL

# TODO (llparse): checkout a branch or tag
RUN git clone https://github.com/openshift/openshift-ansible /openshift-ansible

ADD hosts /etc/ansible/hosts
ADD run.sh /