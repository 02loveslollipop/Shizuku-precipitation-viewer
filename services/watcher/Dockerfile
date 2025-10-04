# Multi-stage Dockerfile for Siata Watcher (Ingest) Service
# Optimized for production deployment

# Stage 1: Build stage
FROM golang:1.24-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git ca-certificates tzdata

# Set working directory
WORKDIR /build

# Copy go mod files first (for better caching)
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy the entire project (needed for internal imports)
COPY . .

# Build the watcher service binary
# CGO_ENABLED=0 for static binary (no external dependencies)
# -ldflags="-s -w" strips debug info to reduce binary size
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-s -w" \
    -o watcher \
    ./services/watcher

# Stage 2: Runtime stage
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache ca-certificates tzdata

# Create non-root user for security
RUN addgroup -g 1001 -S watcher && \
    adduser -u 1001 -S watcher -G watcher

# Set working directory
WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/watcher /app/watcher

# Copy timezone data
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# Set ownership
RUN chown -R watcher:watcher /app

# Switch to non-root user
USER watcher

# Environment variables (can be overridden at runtime)
ENV TZ=UTC \
    SIATA_CURRENT_URL="" \
    DATABASE_URL="" \
    DRY_RUN=false \
    REQUEST_TIMEOUT=30s

# Health check (optional - checks if process is running)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep -x watcher || exit 1

# Run the watcher service
# Note: This is a one-shot service that runs and exits
# For continuous operation, use a cron job or orchestration tool
ENTRYPOINT ["/app/watcher"]
