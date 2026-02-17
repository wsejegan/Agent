package main

import (
	"log"

	"go-agent-service/internal/handler"

	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()

	// Health check (Top level as per README patterns)
	r.GET("/health", handler.HealthHandler)

	// API v1
	v1 := r.Group("/v1")
	{
		v1.GET("/info", handler.InfoHandler)
		v1.POST("/agent/query", handler.QueryHandler)
		v1.GET("/agent/history", handler.HistoryHandler)
		v1.DELETE("/agent/session", handler.ResetHandler)
	}

	log.Printf("🚀 Booking Service (Template) starting on :8080")
	if err := r.Run(":8080"); err != nil {
		log.Fatalf("❌ Failed to start server: %v", err)
	}
}
