package http

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/02loveslollipop/Shizuku-precipitation-viewer/services/api/config"
	"github.com/02loveslollipop/Shizuku-precipitation-viewer/services/api/db"
)

// Server bundles router and dependencies for the REST API.
type Server struct {
	cfg    config.Config
	store  *db.Store
	engine *gin.Engine
}

// New constructs a server with routes and middleware.
func New(cfg config.Config, store *db.Store) *Server {
	gin.SetMode(gin.ReleaseMode)
	engine := gin.New()
	engine.Use(gin.Recovery())
	engine.Use(gin.Logger())
	engine.Use(corsMiddleware())

	if cfg.BearerToken != "" {
		engine.Use(bearerAuthMiddleware(cfg.BearerToken))
	}

	server := &Server{cfg: cfg, store: store, engine: engine}
	server.registerRoutes()
	return server
}

// Engine exposes the underlying gin engine (for tests).
func (s *Server) Engine() *gin.Engine {
	return s.engine
}

// Run starts the HTTP server and blocks until shutdown.
func (s *Server) Run(ctx context.Context) error {
	srv := &http.Server{
		Addr:    s.cfg.ListenAddr(),
		Handler: s.engine,
	}

	errCh := make(chan error, 1)
	go func() {
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
		close(errCh)
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return srv.Shutdown(shutdownCtx)
	}
}

func (s *Server) registerRoutes() {
	s.engine.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	s.engine.GET("/sensor", s.handleListSensors)
	s.engine.GET("/sensor/:sensor_id", s.handleGetSensor)
	s.engine.GET("/now", s.handleLatest)
	s.engine.GET("/grid/latest", s.handleGridLatest)
}

func bearerAuthMiddleware(expected string) gin.HandlerFunc {
	return func(c *gin.Context) {
		auth := c.GetHeader("Authorization")
		if !strings.HasPrefix(auth, "Bearer ") {
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		token := strings.TrimSpace(strings.TrimPrefix(auth, "Bearer "))
		if token != expected {
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		c.Next()
	}
}

func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}

func (s *Server) handleListSensors(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	sensors, err := s.store.ListSensors(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"sensors": sensors})
}

func (s *Server) handleGetSensor(c *gin.Context) {
	sensorID := c.Param("sensor_id")
	if sensorID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "sensor_id is required"})
		return
	}

	useClean := true
	if cleanStr := c.Query("clean"); cleanStr != "" {
		if val, err := strconv.ParseBool(cleanStr); err == nil {
			useClean = val
		} else {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid clean parameter"})
			return
		}
	}

	limit := s.cfg.DefaultLimit
	if limitStr := c.Query("last_n"); limitStr != "" {
		parsed, err := strconv.Atoi(limitStr)
		if err != nil || parsed <= 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid last_n"})
			return
		}
		limit = parsed
	}

	var since *time.Time
	var until *time.Time

	if daysStr := c.Query("last_n_days"); daysStr != "" {
		days, err := strconv.Atoi(daysStr)
		if err != nil || days <= 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid last_n_days"})
			return
		}
		t := time.Now().UTC().Add(-time.Duration(days) * 24 * time.Hour)
		since = &t
	}

	if startStr := c.Query("start"); startStr != "" {
		t, err := time.Parse(time.RFC3339, startStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid start timestamp"})
			return
		}
		tt := t.UTC()
		since = &tt
	}

	if endStr := c.Query("end"); endStr != "" {
		t, err := time.Parse(time.RFC3339, endStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid end timestamp"})
			return
		}
		tt := t.UTC()
		until = &tt
	}

	if since == nil && until == nil && limit <= 0 {
		limit = s.cfg.DefaultLimit
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
	defer cancel()

	measurements, err := s.store.FetchMeasurements(ctx, db.MeasurementQuery{
		SensorID: sensorID,
		UseClean: useClean,
		Limit:    limit,
		Since:    since,
		Until:    until,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"sensor_id":    sensorID,
		"clean":        useClean,
		"count":        len(measurements),
		"measurements": measurements,
	})
}

func (s *Server) handleLatest(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	latest, err := s.store.LatestClean(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"measurements": latest})
}

func (s *Server) handleGridLatest(c *gin.Context) {
	gridURL := strings.TrimRight(s.cfg.BlobBaseURL, "/") + "/" + strings.TrimLeft(s.cfg.GridLatestPath, "/")
	c.JSON(http.StatusOK, gin.H{"grid_url": gridURL})
}
