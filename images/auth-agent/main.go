package main

import (
  "net/http"
  "io/ioutil"
  "bytes"
  "log"
  "fmt"
  "os"
)

const (
  authorizedKeysFile = "/root/.ssh/authorized_keys"
)

func main() {
  http.HandleFunc("/authorized_keys", authorizePublicKey)
  http.HandleFunc("/shutdown", shutdown)
  log.Fatal(http.ListenAndServe(":33518", nil))
}

func authorizePublicKey(w http.ResponseWriter, r *http.Request) {
  if r.Method == "POST" {
    pubkey, err := ioutil.ReadAll(r.Body)
    if err != nil {
      log.Fatal(err)
    }
    log.Printf("Handling public key: %v\n", pubkey)

    if checkAlreadyExists(w, pubkey) {
      log.Println("Public key already authorized")
      w.WriteHeader(http.StatusNoContent)
    } else {
      appendAuthorizedKeysFile(w, pubkey)
    }
  }  
}

func shutdown(w http.ResponseWriter, r *http.Request) {
  fmt.Fprintf(w, "Shutting down")
  os.Exit(0)
}

func checkAlreadyExists(w http.ResponseWriter, pubkey []byte) bool {
  f, err := os.Open(authorizedKeysFile)
  if err != nil {
    log.Fatal(err)
  }
  defer f.Close()

  authFile, err := ioutil.ReadAll(f)
  if err != nil {
    log.Fatal(err)
  }

  return bytes.Contains(authFile, pubkey)
}

func appendAuthorizedKeysFile(w http.ResponseWriter, pubkey []byte) {
  g, err := os.OpenFile(authorizedKeysFile, os.O_WRONLY | os.O_APPEND, 0644)
  if err != nil {
    log.Fatal(err)
  }
  defer g.Close()

  if _, err := g.Write(pubkey); err != nil {
    log.Fatal(err)
  }

  log.Println("Public key added")
  w.WriteHeader(http.StatusCreated)
}
