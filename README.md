# Shizuku Precipitation Viewer

## 🌧️ Try it Live
**[https://shizuku.02labs.me](https://shizuku.02labs.me)**

Experience real-time precipitation visualization for the Medellín metropolitan area with interactive maps, sensor data, and advanced weather analytics.

---

## Introduction

**Shizuku Precipitation Viewer** is a real-time weather monitoring platform that visualizes precipitation data across the Medellín metropolitan area in Colombia. The system integrates with SIATA (Sistema de Alerta Temprana de Medellín) data sources to provide interactive geographic visualization of rainfall patterns, enabling users to understand weather conditions through sophisticated mapping interfaces and data analytics.

The platform combines spatial interpolation algorithms, real-time data processing, and cross-platform mobile visualization to provide weather monitoring.

---

## System Architecture

### Overview
Shizuku implements a **microservices architecture** designed for scalability, reliability, and real-time performance. The system processes data from multiple SIATA weather stations, applies sophisticated quality control and spatial interpolation algorithms, and delivers visualizations through a responsive Flutter application.

[2]

### Core Components

#### 1. **Data Ingestion Layer**
- **Watcher Service** (Go): Continuously monitors SIATA current precipitation feeds
- **Historic Data Processing**: Handles bulk ingestion of historical weather records
- **Data Validation**: Implements input sanitization and duplicate detection

#### 2. **Data Processing Pipeline**
- **Cleaner Service** (Python): Applies quality control, outlier detection, and data imputation
- **ETL Grid Service** (Python): Generates spatial interpolation grids using advanced algorithms
- **Statistical Processing**: Implements temporal analysis and seasonal pattern recognition

#### 3. **Data Storage Layer**
- **PostgreSQL Database**: Primary data store with PostGIS and TimescaleDB extensions
- **Vercel Blob Storage**: Distributed storage for generated visualization artifacts

#### 4. **API & Visualization Layer**
- **REST API Service** (Go): High-performance API with comprehensive endpoints
- **Flutter Mobile App**: Cross-platform visualization client with interactive mapping

### Service Responsibilities

#### **Watcher Service (Go)**
- **Data Source Integration**: Polls `https://siata.gov.co/data/siata_app/Pluviometrica.json` every 10 minutes
- **Sensor Management**: Maintains up-to-date sensor metadata and location information
- **Data Ingestion**: Inserts new precipitation measurements with deduplication logic
- **Quality Assurance**: Filters sentinel values and validates data integrity
- **Error Handling**: Implements robust retry mechanisms and failure notifications

#### **Cleaner Service (Python)**
- **Outlier Detection**: Applies statistical methods including Hampel filters and IQR analysis
- **Quality Control**: Flags measurements based on physical bounds and quality scores  
- **Data Imputation**: Uses gradient-boosted forecasting with temporal feature engineering
- **Gap Filling**: Implements multiple imputation strategies for missing data
- **Validation**: Ensures cleaned data maintains scientific accuracy and completeness

#### **ETL Grid Service (Python)**
- **Spatial Interpolation**: Generates precipitation grids using cubic spline interpolation
- **Coordinate Transformation**: Projects data between WGS84 and Web Mercator systems
- **Grid Processing**: Creates 500-meter resolution grids with advanced algorithms
- **Artifact Generation**: Produces compressed JSON, NPZ, and visualization formats
- **Contour Generation**: Calculates precipitation contour lines for mapping overlays

#### **REST API Service (Go)**
- **Sensor Endpoints**: Provides comprehensive sensor metadata and measurement queries
- **Grid Access**: Serves latest precipitation grids and historical grid collections  
- **Authentication**: Implements bearer token security for protected endpoints
- **CORS Management**: Handles cross-origin requests for web applications
- **Performance Optimization**: Includes connection pooling and query optimization

#### **Flutter Application**
- **Interactive Mapping**: MapLibre GL integration with custom precipitation overlays
- **Data Visualization**: FL Chart implementation for time-series and statistical plots
- **Real-time Updates**: Live precipitation data with automatic refresh capabilities
- **Cross-platform Support**: Native performance on iOS, Android, and web platforms
- **Offline Capability**: Caches essential data for offline viewing

### Database Schema

#### **Core Tables**
- **`sensors`**: Station metadata including coordinates, elevation, and regional classifications
- **`raw_measurements`**: Unprocessed precipitation data with source attribution and quality scores
- **`clean_measurements`**: Quality-controlled data with imputation flags and processing metadata  
- **`grid_runs`**: Spatial interpolation job status and artifact references


### Data Flow Architecture

The system implements a sophisticated data pipeline that transforms raw sensor measurements into interactive visualizations:

1. **Data Collection**: Watcher service continuously polls SIATA feeds for new measurements
2. **Quality Processing**: Cleaner service applies statistical analysis and imputation algorithms  
3. **Spatial Analysis**: ETL service generates interpolated precipitation grids using advanced algorithms
4. **Storage Management**: Processed artifacts are uploaded to Vercel Blob storage
5. **API Delivery**: REST service provides endpoints for various client applications
6. **Visualization**: Flutter application renders interactive maps and analytical interfaces

---

## Running Instructions

### Prerequisites
- **Go 1.23+**: Required for API services and watcher components
- **Python 3.11+**: Needed for data processing and analysis services
- **PostgreSQL 15+**: Database with PostGIS and TimescaleDB extensions
- **Flutter SDK 3.7+**: Cross-platform application development

### Environment Configuration

Create a `.env` file in the project root:

```bash
# Database Configuration
DATABASE_URL=postgres://username:password@host:port/database?sslmode=require

# External Service Integration  
VERCEL_BLOB_BASE_URL=https://your-blob-storage.vercel-storage.com
VERCEL_BLOB_RW_TOKEN=vercel_blob_rw_token_here

# SIATA Data Sources
CURRENT_URL=https://siata.gov.co/data/siata_app/Pluviometrica.json
HISTORIC_URL=https://datosabiertos.metropol.gov.co/sites/default/files/uploaded_resources/Datos_SIATA_Vaisala_precipitacion_0.json

# API Service Configuration
API_PORT=8080
API_BEARER_TOKEN=optional_authentication_token
CORS_ALLOWED_ORIGINS=*

# Processing Parameters
GRID_RES_M=500
BBOX_PADDING_M=5000
CLEANER_LOOKBACK_HOURS=72
WATCHER_MIN_INTERVAL=5m
```

### Database Setup

1. **Create PostgreSQL Database**:
```bash
createdb shizuku_precipitation
```

2. **Install Extensions**:
```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS timescaledb;
```

3. **Apply Schema**:
```bash
psql $DATABASE_URL -f db/schema.sql
```

### Local Development

#### **Backend Services**

**Start API Service**:
```bash
cd services/api
go mod download
go run main.go
```

**Run Data Watcher**:
```bash  
cd services/watcher
go run main.go
```

**Execute Data Cleaner**:
```bash
pip install -r requirements.txt
python -m services.cleaner.main
```

**Process Grid Generation**:
```bash
python -m services.etl.main
```

#### **Frontend Application**

**Flutter Development**:
```bash
cd apps/shizuka_viewer
flutter pub get
flutter run -d chrome  # or your preferred target
```

### Production Deployment

#### **Heroku Configuration**

1. **Create Heroku Applications**:
```bash
heroku create shizuku-api --buildpack heroku/go
heroku create shizuku-watcher --buildpack heroku/go  
heroku create shizuku-processor --buildpack heroku/python
```

2. **Configure Environment Variables**:
```bash
heroku config:set DATABASE_URL=$DATABASE_URL --app shizuku-api
heroku config:set VERCEL_BLOB_BASE_URL=$VERCEL_BLOB_BASE_URL --app shizuku-api
# Repeat for all applications with relevant variables
```

3. **Deploy Services**:
```bash
git subtree push --prefix=services/api heroku-api main
git subtree push --prefix=services/watcher heroku-watcher main
```

4. **Schedule Background Jobs**:
- Configure Heroku Scheduler for watcher service: `bin/watcher` (every 10 minutes)
- Configure Heroku Scheduler for cleaner service: `python -m services.cleaner.main` (hourly)
- Configure Heroku Scheduler for ETL service: `python -m services.etl.main` (hourly)

#### **Flutter Web Deployment**

```bash
cd apps/shizuka_viewer
flutter build web --release
# Deploy build/web directory to your preferred hosting platform
```

---

## Acknowledgements & Thanks

### Data Sources
- **SIATA (Sistema de Alerta Temprana de Medellín)**: For providing comprehensive precipitation data and real-time weather monitoring infrastructure

### Technology Partners  
- **Heroku**: Cloud platform enabling scalable deployment and scheduler management
- **Vercel**: Blob storage infrastructure for efficient artifact distribution
- **PostgreSQL Community**: For robust database technology with geospatial and time-series extensions


### Open Source Community
- **Flutter Team**: Cross-platform framework enabling consistent user experiences
- **Go Community**: High-performance programming language ecosystem for concurrent backend services
- **Python Scientific Stack**: NumPy, SciPy, Pandas, and scikit-learn for data processing excellence
- **PostGIS & TimescaleDB**: Geospatial and time-series database extensions

---

*Shizuku (雫) - Japanese for "droplet" - represents the fundamental unit of precipitation that, when aggregated across space and time, reveals the complex patterns of our atmospheric environment.*