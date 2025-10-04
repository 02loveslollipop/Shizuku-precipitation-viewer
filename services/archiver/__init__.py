"""
Data Archiver Service

This service archives old measurements to blob storage and cleans up the database:
1. Deletes raw measurements older than 24 hours
2. Archives clean measurements older than 30 days to blob storage
3. Deletes archived clean measurements from the database

Runs daily as a scheduled task.
"""

__version__ = "1.0.0"
