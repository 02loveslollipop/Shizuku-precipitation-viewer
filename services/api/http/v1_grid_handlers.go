package http

import (
	"context"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

// handleV1GridTimestamps returns paginated list of grid timestamps with aggregate stats
// GET /api/v1/grid/timestamps?page=1&limit=20&start=2024-01-01T00:00:00Z&end=2024-12-31T23:59:59Z
func (s *Server) handleV1GridTimestamps(c *gin.Context) {
	// Parse pagination parameters
	page := 1
	if p := c.Query("page"); p != "" {
		if val, err := strconv.Atoi(p); err == nil && val > 0 {
			page = val
		}
	}

	limit := 20
	if l := c.Query("limit"); l != "" {
		if val, err := strconv.Atoi(l); err == nil && val > 0 && val <= 100 {
			limit = val
		}
	}

	offset := (page - 1) * limit

	// Parse optional time range filters
	var startTime, endTime *time.Time
	if start := c.Query("start"); start != "" {
		if t, err := time.Parse(time.RFC3339, start); err == nil {
			startTime = &t
		} else {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid start time format, expected RFC3339"})
			return
		}
	}
	if end := c.Query("end"); end != "" {
		if t, err := time.Parse(time.RFC3339, end); err == nil {
			endTime = &t
		} else {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid end time format, expected RFC3339"})
			return
		}
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
	defer cancel()

	// Get paginated grid runs with aggregates
	result, err := s.store.ListGridTimestampsWithAggregates(ctx, limit, offset, startTime, endTime)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": result.Grids,
		"pagination": gin.H{
			"page":        page,
			"limit":       limit,
			"total_count": result.TotalCount,
			"total_pages": (result.TotalCount + limit - 1) / limit,
		},
	})
}

// handleV1GridByTimestamp returns grid data for a specific timestamp
// GET /api/v1/grid/:timestamp
func (s *Server) handleV1GridByTimestamp(c *gin.Context) {
	timestampStr := c.Param("timestamp")
	if timestampStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "timestamp is required"})
		return
	}

	timestamp, err := time.Parse(time.RFC3339, timestampStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid timestamp format, expected RFC3339"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
	defer cancel()

	grid, err := s.store.GetGridRunByTimestamp(ctx, timestamp)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if grid == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "grid not found for timestamp"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": grid,
	})
}

// handleV1GridSensorAggregates returns sensor aggregates for a specific grid timestamp
// GET /api/v1/grid/:timestamp/sensors
func (s *Server) handleV1GridSensorAggregates(c *gin.Context) {
	timestampStr := c.Param("timestamp")
	if timestampStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "timestamp is required"})
		return
	}

	timestamp, err := time.Parse(time.RFC3339, timestampStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid timestamp format, expected RFC3339"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
	defer cancel()

	aggregates, err := s.store.GetSensorAggregatesByTimestamp(ctx, timestamp)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": aggregates,
		"meta": gin.H{
			"timestamp": timestamp.Format(time.RFC3339),
			"count":     len(aggregates),
		},
	})
}

// handleV1GridContours returns contours GeoJSON URL for a specific grid
// GET /api/v1/grid/:timestamp/contours
func (s *Server) handleV1GridContours(c *gin.Context) {
	timestampStr := c.Param("timestamp")
	if timestampStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "timestamp is required"})
		return
	}

	timestamp, err := time.Parse(time.RFC3339, timestampStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid timestamp format, expected RFC3339"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	grid, err := s.store.GetGridRunByTimestamp(ctx, timestamp)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if grid == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "grid not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"contours_url": grid.BlobURLContours,
			"timestamp":    timestamp.Format(time.RFC3339),
		},
	})
}

// Note: Preview JPEG URLs are not stored in the database.
// They are available in the blob storage latest.json file
// and can be accessed via the /api/v1/realtime/now endpoint.
