package http

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// handleV1RealtimeNow returns the latest grid data with sensor aggregates
// GET /api/v1/realtime/now
func (s *Server) handleV1RealtimeNow(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
	defer cancel()

	// Get latest successful grid run
	grid, err := s.store.GetLatestGrid(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if grid == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "no grid data available"})
		return
	}

	// Get sensor aggregates for this grid
	aggregates, err := s.store.GetSensorAggregatesByGridRunID(ctx, grid.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"grid":              grid,
			"sensor_aggregates": aggregates,
		},
		"meta": gin.H{
			"timestamp":     grid.Timestamp.Format(time.RFC3339),
			"sensors_count": len(aggregates),
			"generated_at":  time.Now().UTC().Format(time.RFC3339),
		},
	})
}
