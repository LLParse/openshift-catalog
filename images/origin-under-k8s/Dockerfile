FROM python:2.7

RUN \
  git clone https://github.com/LLParse/openshift-under-kubernetes /openshift-under-kubernetes && \
  cd /openshift-under-kubernetes && \
  python setup.py install && \
  cd / && \
  rm -rf /openshift-under-kubernetes

ENTRYPOINT ["openshift-under-kubernetes"]
