package handler

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
)

var startTime = time.Now()
var history []map[string]interface{}

// HealthHandler returns the system health status
func HealthHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status": "ok",
		"time":   time.Now().Format(time.RFC3339),
	})
}

// InfoHandler returns service information
func InfoHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"name":    "go-agent-service",
		"version": "1.0.0",
		"runtime": "go1.22",
	})
}

// QueryHandler handles agent queries via OpenRouter
func QueryHandler(c *gin.Context) {
	var input struct {
		Prompt string `json:"prompt" binding:"required"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "prompt is required"})
		return
	}

	apiKey := os.Getenv("OPENROUTER_API_KEY")
	if apiKey == "" {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "OPENROUTER_API_KEY not set"})
		return
	}

	// Call OpenRouter
	payload := map[string]interface{}{
		"model": "anthropic/claude-3-sonnet",
		"messages": []map[string]string{
			{"role": "user", "content": input.Prompt},
		},
	}
	jsonData, _ := json.Marshal(payload)

	req, _ := http.NewRequest("POST", "https://openrouter.ai/api/v1/chat/completions", bytes.NewBuffer(jsonData))
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": fmt.Sprintf("failed to contact OpenRouter: %v", err)})
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "invalid response from OpenRouter"})
		return
	}

	// Record history
	interaction := map[string]interface{}{
		"timestamp": time.Now().Format(time.RFC3339),
		"prompt":    input.Prompt,
		"response":  result,
	}
	history = append(history, interaction)

	c.JSON(http.StatusOK, result)
}

// HistoryHandler returns past agent interactions
func HistoryHandler(c *gin.Context) {
	c.JSON(http.StatusOK, history)
}

// ResetHandler clears the history
func ResetHandler(c *gin.Context) {
	history = []map[string]interface{}{}
	c.Status(http.StatusNoContent)
}
