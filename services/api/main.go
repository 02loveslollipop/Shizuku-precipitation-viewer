package main

import (
	"context"
	"log"
	"os/signal"
	"syscall"

	"github.com/02loveslollipop/Shizuku-precipitation-viewer/services/api/config"
	"github.com/02loveslollipop/Shizuku-precipitation-viewer/services/api/db"
	httpserver "github.com/02loveslollipop/Shizuku-precipitation-viewer/services/api/http"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config error: %v", err)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	store, err := db.New(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("db connection error: %v", err)
	}
	defer store.Close()

	srv := httpserver.New(cfg, store)
	log.Printf("REST API listening on %s", cfg.ListenAddr())

	if err := srv.Run(ctx); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
