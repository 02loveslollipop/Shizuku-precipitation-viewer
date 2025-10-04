# Dockerfile for Data Archiver Service
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy archiver service
COPY services/archiver /app/archiver

# Set Python path
ENV PYTHONPATH=/app

# Run the archiver
CMD ["python", "-m", "archiver.main"]
