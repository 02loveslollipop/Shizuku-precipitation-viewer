package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

const (
	defaultCurrentURL     = "https://siata.gov.co/data/siata_app/Pluviometrica.json"
	defaultMinInterval    = 5 * time.Minute
	defaultRequestTimeout = 30 * time.Second
	defaultValueEpsilon   = 0.01
)

// Config holds runtime configuration for the watcher service.
type Config struct {
	DatabaseURL    string
	CurrentURL     string
	MinInterval    time.Duration
	RequestTimeout time.Duration
	ValueEpsilon   float64
	DryRun         bool
}

// Load reads configuration from environment variables (optionally .env).
func Load() (Config, error) {
	_ = godotenv.Load(".env")

	cfg := Config{}

	cfg.DatabaseURL = strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if cfg.DatabaseURL == "" {
		return cfg, errors.New("DATABASE_URL is required")
	}

	cfg.CurrentURL = strings.TrimSpace(os.Getenv("CURRENT_URL"))
	if cfg.CurrentURL == "" {
		cfg.CurrentURL = defaultCurrentURL
	}

	cfg.MinInterval = defaultMinInterval
	if v := strings.TrimSpace(os.Getenv("WATCHER_MIN_INTERVAL")); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil {
			return cfg, fmt.Errorf("invalid WATCHER_MIN_INTERVAL: %w", err)
		}
		cfg.MinInterval = d
	}

	cfg.RequestTimeout = defaultRequestTimeout
	if v := strings.TrimSpace(os.Getenv("WATCHER_REQUEST_TIMEOUT")); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil {
			return cfg, fmt.Errorf("invalid WATCHER_REQUEST_TIMEOUT: %w", err)
		}
		cfg.RequestTimeout = d
	}

	cfg.ValueEpsilon = defaultValueEpsilon
	if v := strings.TrimSpace(os.Getenv("WATCHER_VALUE_EPSILON")); v != "" {
		f, err := strconv.ParseFloat(v, 64)
		if err != nil {
			return cfg, fmt.Errorf("invalid WATCHER_VALUE_EPSILON: %w", err)
		}
		cfg.ValueEpsilon = f
	}

	dryRun := strings.TrimSpace(os.Getenv("DRY_RUN"))
	cfg.DryRun = dryRun == "1" || strings.EqualFold(dryRun, "true")

	return cfg, nil
}
