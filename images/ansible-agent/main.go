package main

import (
  "github.com/rancher/go-rancher-metadata/metadata"
  "log"
)

const (
  metadataUrl = "http://rancher-metadata/2015-12-19"
)

func main() {
  m := metadata.NewClient(metadataUrl)
  
  service, err := m.GetSelfServiceByName("ansible-agent")
  if err != nil {
    log.Fatal(err)
  }

  for _, container := range service.Containers {
    log.Println(container)
  }
}