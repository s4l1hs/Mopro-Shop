package main

import (
	"log"
	"os"
)

func main() {
	market := os.Getenv("MARKET")
	log.Printf("starting jobs-svc market=%s", market)
}
