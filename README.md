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

- Go 1.23+
- Python 3.11+
- PostgreSQL 15+ (with PostGIS and TimescaleDB)
- Flutter SDK 3.7+

### Environment (example)

Create a `.env` file in the project root with values like:

```
DATABASE_URL=postgres://username:password@host:port/database?sslmode=require
VERCEL_BLOB_BASE_URL=https://your-blob-storage.vercel-storage.com
CURRENT_URL=https://siata.gov.co/data/siata_app/Pluviometrica.json
API_PORT=8080
```

### Local development quick start

Backend services

1. API service

```
cd services/api
go mod download
go run main.go
```

2. Watcher service

```
cd services/watcher
go run main.go
```

3. Cleaner / ETL

```
pip install -r requirements.txt
python -m services.cleaner.main
python -m services.etl.main
```

Flutter app

```
cd apps/shizuka_viewer
flutter pub get
flutter run -d chrome
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
