package config

import (
	"errors"
	"fmt"
	"github.com/joho/godotenv"
	"os"
	"strconv"
)

// Config holds environment-driven settings for the REST API.
type Config struct {
	DatabaseURL    string
	BlobBaseURL    string
	GridLatestPath string
	Port           int
	BearerToken    string
	DefaultLimit   int
	DefaultDays    int
}

// Load reads configuration from environment variables (optionally .env).
func Load() (Config, error) {
	_ = godotenv.Load() // ignore missing file

	cfg := Config{
		GridLatestPath: "grids/latest.json",
		Port:           8080,
		DefaultLimit:   200,
		DefaultDays:    7,
	}

	cfg.DatabaseURL = os.Getenv("DATABASE_URL")
	if cfg.DatabaseURL == "" {
		return cfg, errors.New("DATABASE_URL is required")
	}

	cfg.BlobBaseURL = os.Getenv("VERCEL_BLOB_BASE_URL")
	if cfg.BlobBaseURL == "" {
		return cfg, errors.New("VERCEL_BLOB_BASE_URL is required")
	}

	if path := os.Getenv("GRID_LATEST_PATH"); path != "" {
		cfg.GridLatestPath = path
	}

	if portStr := os.Getenv("PORT"); portStr != "" {
		if port, err := strconv.Atoi(portStr); err == nil && port > 0 {
			cfg.Port = port
		} else {
			return cfg, fmt.Errorf("invalid PORT: %s", portStr)
		}
	} else if portStr := os.Getenv("API_PORT"); portStr != "" {
		if port, err := strconv.Atoi(portStr); err == nil && port > 0 {
			cfg.Port = port
		} else {
			return cfg, fmt.Errorf("invalid API_PORT: %s", portStr)
		}
	}

	if limitStr := os.Getenv("API_DEFAULT_LIMIT"); limitStr != "" {
		if limit, err := strconv.Atoi(limitStr); err == nil && limit > 0 {
			cfg.DefaultLimit = limit
		} else {
			return cfg, fmt.Errorf("invalid API_DEFAULT_LIMIT: %s", limitStr)
		}
	}

	if daysStr := os.Getenv("API_DEFAULT_DAYS"); daysStr != "" {
		if days, err := strconv.Atoi(daysStr); err == nil && days > 0 {
			cfg.DefaultDays = days
		} else {
			return cfg, fmt.Errorf("invalid API_DEFAULT_DAYS: %s", daysStr)
		}
	}

	cfg.BearerToken = os.Getenv("API_BEARER_TOKEN")

	return cfg, nil
}

// ListenAddr returns the host:port string for the HTTP server.
func (c Config) ListenAddr() string {
	return fmt.Sprintf(":%d", c.Port)
}
