package http

// registerV1Routes sets up the new v1 API structure
// Groups: /api/v1/core, /api/v1/grid, /api/v1/realtime
func (s *Server) registerV1Routes() {
	v1 := s.engine.Group("/api/v1")
	v1.Use(apiVersionMiddleware()) // Add X-API-Version: v1 header

	// Core endpoints - sensor data and metadata
	core := v1.Group("/core")
	{
		core.GET("/sensors", s.handleV1ListSensors)
		core.GET("/sensors/:id", s.handleV1GetSensor)
	}

	// Grid endpoints - grid data with pagination and aggregates
	grid := v1.Group("/grid")
	{
		grid.GET("/timestamps", s.handleV1GridTimestamps)
		grid.GET("/:timestamp", s.handleV1GridByTimestamp)
		grid.GET("/:timestamp/sensors", s.handleV1GridSensorAggregates)
		grid.GET("/:timestamp/contours", s.handleV1GridContours)
		// Note: Preview JPEG URLs are available in the /realtime/now endpoint's latest.json
	}

	// Realtime endpoints - latest data
	realtime := v1.Group("/realtime")
	{
		realtime.GET("/now", s.handleV1RealtimeNow)
	}
}
