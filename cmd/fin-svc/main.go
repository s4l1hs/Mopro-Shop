package main

import (
	"log"
	"os"
)

func main() {
	market := os.Getenv("MARKET")
	log.Printf("starting fin-svc market=%s", market)
}
