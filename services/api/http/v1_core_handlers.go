package http

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// handleV1ListSensors returns all sensors
// GET /api/v1/core/sensors
func (s *Server) handleV1ListSensors(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	sensors, err := s.store.ListSensors(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": sensors,
		"meta": gin.H{
			"count": len(sensors),
		},
	})
}

// handleV1GetSensor returns details for a specific sensor
// GET /api/v1/core/sensors/:id
func (s *Server) handleV1GetSensor(c *gin.Context) {
	sensorID := c.Param("id")
	if sensorID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "sensor id is required"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	sensor, err := s.store.GetSensor(ctx, sensorID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if sensor == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "sensor not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": sensor,
	})
}
