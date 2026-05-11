package main

import (
	"log"
	"os"
)

func main() {
	market := os.Getenv("MARKET")
	log.Printf("starting core-svc market=%s", market)
}
