package http

import (
	"context"
	encjson "encoding/json"
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
	engine.Use(corsMiddleware(cfg))

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

	// Legacy endpoints (v0) - with deprecation warnings
	legacy := s.engine.Group("/")
	legacy.Use(deprecationMiddleware())
	{
		legacy.GET("/sensor", deprecatedHandler("/api/v1/core/sensors", s.handleListSensors))
		legacy.GET("/sensor/:sensor_id", deprecatedHandler("/api/v1/core/sensors/:sensor_id", s.handleGetSensor))
		legacy.GET("/now", deprecatedHandler("/api/v1/realtime/now", s.handleLatest))
		legacy.GET("/grid/latest", deprecatedHandler("/api/v1/realtime/now", s.handleGridLatest))
		legacy.GET("/grid/available", deprecatedHandler("/api/v1/grid/timestamps", s.handleGridAvailable))
		legacy.GET("/grid/:timestamp", deprecatedHandler("/api/v1/grid/:timestamp", s.handleGridByTimestamp))
		legacy.GET("/dashboard/summary", deprecatedHandler("", s.handleDashboardSummary)) // No v1 equivalent yet
		legacy.GET("/snapshot", deprecatedHandler("", s.handleSnapshotAt))                // No v1 equivalent yet
	}

	// New versioned API routes
	s.registerV1Routes()
}

func (s *Server) handleSnapshotAt(c *gin.Context) {
	tsStr := c.Query("ts")
	if tsStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ts query parameter required (RFC3339)"})
		return
	}
	ts, err := time.Parse(time.RFC3339, tsStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid ts format, expected RFC3339"})
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
	defer cancel()

	snaps, err := s.store.SnapshotAtTimestamp(ctx, ts, useClean)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Build response: include requested timestamp and measurements
	c.JSON(http.StatusOK, gin.H{
		"requested_ts": ts.Format(time.RFC3339),
		"measurements": snaps,
	})
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

func corsMiddleware(cfg config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")

		// Check if origin is allowed
		allowedOrigins := strings.Split(cfg.CORSAllowedOrigins, ",")
		allowOrigin := false

		for _, allowed := range allowedOrigins {
			allowed = strings.TrimSpace(allowed)
			if allowed == "*" || allowed == origin {
				allowOrigin = true
				break
			}
		}

		if allowOrigin {
			c.Header("Access-Control-Allow-Origin", origin)
		}

		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if cfg.CORSAllowCredentials {
			c.Header("Access-Control-Allow-Credentials", "true")
		}

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}

// deprecationMiddleware adds API version headers to all responses
func deprecationMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Add API version header to all responses
		c.Header("X-API-Version", "v0-legacy")
		c.Next()
	}
}

// deprecatedHandler wraps a handler and adds deprecation headers
func deprecatedHandler(newEndpoint string, handler gin.HandlerFunc) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Mark this endpoint as deprecated
		c.Header("X-Deprecated-Endpoint", "true")

		// Provide the new endpoint URL if available
		if newEndpoint != "" {
			c.Header("X-New-Endpoint", newEndpoint)
			// Standard Deprecation header with sunset date (6 months from now)
			sunsetDate := time.Now().AddDate(0, 6, 0).Format(time.RFC1123)
			c.Header("Deprecation", "true")
			c.Header("Sunset", sunsetDate)
		}

		// Add a warning header
		if newEndpoint != "" {
			c.Header("Warning", `299 - "This endpoint is deprecated and will be removed in 6 months. Use `+newEndpoint+` instead."`)
		} else {
			c.Header("Warning", `299 - "This endpoint is deprecated. Please contact support for migration guidance."`)
		}

		// Call the original handler
		handler(c)
	}
}

// apiVersionMiddleware adds API version header to v1 responses
func apiVersionMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("X-API-Version", "v1")
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

func (s *Server) handleGridAvailable(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	timestamps, err := s.store.GetAvailableGridTimestamps(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Convert timestamps to RFC3339 strings for JSON response
	timestampStrings := make([]string, len(timestamps))
	for i, ts := range timestamps {
		timestampStrings[i] = ts.Format(time.RFC3339)
	}

	response := gin.H{
		"timestamps": timestampStrings,
	}

	// Add latest timestamp if available (timestamps are ordered ASC; pick last element)
	if len(timestamps) > 0 {
		response["latest"] = timestamps[len(timestamps)-1].Format(time.RFC3339)
	}

	c.JSON(http.StatusOK, response)
}

func (s *Server) handleGridByTimestamp(c *gin.Context) {
	timestampStr := c.Param("timestamp")
	if timestampStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "timestamp parameter is required"})
		return
	}

	timestamp, err := time.Parse(time.RFC3339, timestampStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid timestamp format, expected RFC3339"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	gridInfo, err := s.store.GetGridByTimestamp(ctx, timestamp)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "grid not found for timestamp"})
		return
	}

	response := gin.H{
		"timestamp": gridInfo.Timestamp.Format(time.RFC3339),
		"status":    gridInfo.Status,
	}

	if gridInfo.GridURL != nil {
		response["grid_url"] = *gridInfo.GridURL
	}
	if gridInfo.ContoursURL != nil {
		response["contours_url"] = *gridInfo.ContoursURL
	}
	if len(gridInfo.Bounds) > 0 {
		response["bounds"] = gridInfo.Bounds
	}

	c.JSON(http.StatusOK, response)
}

func (s *Server) handleDashboardSummary(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
	defer cancel()

	averages, err := s.store.GetAverages(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Attempt to retrieve grid latest pointer to extract any preview URL
	gridURL := strings.TrimRight(s.cfg.BlobBaseURL, "/") + "/" + strings.TrimLeft(s.cfg.GridLatestPath, "/")
	previewURL := ""
	if gridURL != "" {
		// fetch pointer JSON from blob store (best-effort)
		client := &http.Client{Timeout: 10 * time.Second}
		if resp, err := client.Get(gridURL); err == nil {
			defer resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				var ptr map[string]interface{}
				if err := encjson.NewDecoder(resp.Body).Decode(&ptr); err == nil {
					// ETL may store grid_preview_jpeg_url or preview_jpeg_url
					if v, ok := ptr["grid_preview_jpeg_url"].(string); ok && v != "" {
						previewURL = v
					} else if v, ok := ptr["preview_jpeg_url"].(string); ok && v != "" {
						previewURL = v
					}
				}
			}
		}
	}

	resp := gin.H{"averages": gin.H{}}
	if averages != nil {
		if averages.Avg3h != nil {
			resp["averages"].(gin.H)["3h"] = *averages.Avg3h
		} else {
			resp["averages"].(gin.H)["3h"] = nil
		}
		if averages.Avg6h != nil {
			resp["averages"].(gin.H)["6h"] = *averages.Avg6h
		} else {
			resp["averages"].(gin.H)["6h"] = nil
		}
		if averages.Avg12h != nil {
			resp["averages"].(gin.H)["12h"] = *averages.Avg12h
		} else {
			resp["averages"].(gin.H)["12h"] = nil
		}
		if averages.Avg24h != nil {
			resp["averages"].(gin.H)["24h"] = *averages.Avg24h
		} else {
			resp["averages"].(gin.H)["24h"] = nil
		}
	}

	if previewURL != "" {
		resp["grid_preview_jpeg_url"] = previewURL
	}

	c.JSON(http.StatusOK, resp)
}
