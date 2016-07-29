FROM centos:centos7

RUN \
  yum install -y openssh-server PyYAML && \
  curl -L https://get.docker.com/builds/Linux/x86_64/docker-1.10.3 -o /usr/bin/docker && \
  chmod +x /usr/bin/docker
# iproute? net-tools?

ADD run.sh /
CMD ["/run.sh"]