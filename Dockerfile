# Multi-stage Dockerfile for Siata API Service
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

# Build the API service binary
# CGO_ENABLED=0 for static binary (no external dependencies)
# -ldflags="-s -w" strips debug info to reduce binary size
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-s -w" \
    -o api \
    ./services/api

# Stage 2: Runtime stage
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache ca-certificates tzdata

# Create non-root user for security
RUN addgroup -g 1001 -S api && \
    adduser -u 1001 -S api -G api

# Set working directory
WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/api /app/api

# Copy timezone data
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# Set ownership
RUN chown -R api:api /app

# Switch to non-root user
USER api

# Expose port (default 8080, can be overridden by PORT env var)
EXPOSE 8080

# Run the binary
CMD ["/app/api"]
