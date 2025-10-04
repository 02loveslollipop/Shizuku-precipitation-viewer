#!/bin/bash
# Cron script to run the data archiver service

# Set working directory
cd "$(dirname "$0")/../.."

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    source venv/bin/activate
fi

# Load environment variables
if [ -f ".env" ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Run the archiver
echo "==================================="
echo "Starting Data Archiver Service"
echo "Time: $(date)"
echo "==================================="

python -m services.archiver.main

EXIT_CODE=$?

echo "==================================="
echo "Archiver finished with exit code: $EXIT_CODE"
echo "Time: $(date)"
echo "==================================="

exit $EXIT_CODE
