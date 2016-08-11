FROM centos:centos7

RUN yum install -y PyYAML

# TODO: docker via systemd, methinks...
RUN \
  yum install -y iproute openssh-server && \
  curl -L https://get.docker.com/builds/Linux/x86_64/docker-1.10.3 -o /usr/bin/docker && \
  chmod +x /usr/bin/docker

# net-tools?

ADD auth-agent /usr/bin/
ADD systemd/system-unit/* /usr/lib/systemd/system/
ADD systemd/system-preset/* /usr/lib/systemd/system-preset/