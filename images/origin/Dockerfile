# TODO: 1.3.0 is out
FROM openshift/origin:v1.2.1

RUN \
  curl -L https://github.com/cloudnautique/giddyup/releases/download/v0.14.0/giddyup -o /usr/bin/giddyup && \
  chmod +x /usr/bin/giddyup && \
  yum install -y jq unzip 

WORKDIR /etc/origin
ADD run.sh examples_v1.2.tgz /
ADD config /root/.kube/config
ENTRYPOINT ["/run.sh"]