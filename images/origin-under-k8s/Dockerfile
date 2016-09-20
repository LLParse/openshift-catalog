FROM python:2.7

RUN apt-get update && apt-get install -y vim jq unzip

RUN \
  git clone https://github.com/LLParse/openshift-under-kubernetes /openshift-under-kubernetes && \
  cd /openshift-under-kubernetes && \
  python setup.py install && \
  cd / && \
  rm -rf /openshift-under-kubernetes && \
  echo 4

ADD run.sh /
ENTRYPOINT ["/run.sh"]
