<div align="center">
	<img src="apps/shizuka_viewer/assets/icons/shizuku_logo.svg" alt="Shizuku Logo" width="120"/>
	<h1>Shizuku</h1>
	<p>
	</p>
	<p><em>Real-time precipitation visualization for the Medellín metropolitan area with interactive maps and sensor analytics.</em></p>
</div>

## 🌧️ Try it Live

[https://shizuku.02labs.me](https://shizuku.02labs.me)

---

## 📌 Introduction

Shizuku Precipitation Viewer is a real-time weather monitoring platform that visualizes precipitation across the Medellín metropolitan area. The system integrates with SIATA (Sistema de Alerta Temprana de Medellín) data sources and provides interactive geographic visualization, sensor time-series, and spatial interpolation artifacts.

## 🏗️ System Architecture (summary)

Shizuku uses a microservices architecture for scalability and real-time processing. The main responsibilities are:

- Watcher service (Go): polls SIATA, ingests measurements, deduplicates and validates data.
- Cleaner service (Python): quality control, outlier detection, and imputation.
- ETL/Grid service (Python): builds interpolated precipitation grids and contours.
- API service (Go): serves sensors, measurements, and grid artifacts.
- Flutter app: cross-platform visualization client.

## 🚀 Running Instructions

### Prerequisites
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
## 📚 Database schema & data flow (short)

- Core tables: `sensors`, `raw_measurements`, `clean_measurements`, `grid_runs`.
- Flow: Watcher -> Cleaner -> ETL grids -> Storage (Vercel) -> API -> App

---

## 📦 Production & Deployment notes

- Heroku apps can be created for API, watcher and processor. Configure `DATABASE_URL` and other env vars accordingly. Use Heroku Scheduler for periodic jobs.
- Flutter web can be built with `flutter build web --release` and deployed to your hosting provider.

---

## 🙏 Acknowledgements

- SIATA for data
- PostGIS & TimescaleDB
- Flutter, Go and Python open-source ecosystems

---

*Shizuku (雫) — Japanese for "droplet" — represents the unit of precipitation used by this project.*
