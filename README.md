# FEASTLINK — Surplus Food Redistribution System

A full-stack Next.js application for connecting event organizers who have surplus food with shelter homes that can use it. Built from the FEASTLINK project report and designed to demonstrate the PES University DBMS Level 3 evaluation criteria.

## Stack

- **Frontend:** Next.js 14 App Router, React, TypeScript, custom responsive UI
- **Backend:** Next.js Route Handlers (REST API)
- **Primary database:** MySQL 8+ / InnoDB for relational, transactional business data
- **NoSQL database:** MongoDB for append-only activity logs and notifications
- **Authentication:** bcrypt password hashing + signed JWT in an HttpOnly cookie

## Features

- Organizer and Shelter Admin registration/login, plus Admin role support in the database
- Organizer dashboard, event and surplus-food listing workflow
- Shelter food discovery and meal request workflow
- Organizer approval/rejection of requests; approval creates allocation and delivery records atomically
- Delivery progression: Pending → Picked up → In transit → Delivered
- Shelter donation-history capture after delivery, including meals served and beneficiary count
- Role-scoped request, delivery and impact-history views
- Dashboard metrics, responsive layouts, search, validation, status badges and audit logging

## Database design

The MySQL schema follows the eight entities and relationships in the project report (Users, Events, Shelter Homes, Surplus Food, Food Requests, Food Allocations, Delivery, Donation History). It adds practical indexes, CHECK constraints and timestamps while preserving the report's one-to-many and optional one-to-one relationships.

### Advanced DBMS concepts implemented

1. **Trigger** `trg_request_approved`: synchronizes a food listing's status when a request is approved or released.
2. **Stored function** `meals_remaining(food_id)`: calculates remaining meal capacity.
3. **Stored procedure** `approve_food_request(request_id, allocated_meals)`: validates and creates an allocation + delivery record.
4. **Transactions**: registration, food publishing, request creation, approval and donation-history recording use explicit `BEGIN`, `COMMIT`, `ROLLBACK` boundaries in the API.
5. **Indexes**: composite status/expiry indexes, foreign-key lookup indexes, unique constraints and a FULLTEXT food-name index.
6. **Joins and aggregation**: dashboard, request, delivery and impact reports use multi-table joins; `v_food_distribution` is a join-backed reporting view.

MongoDB is deliberately not used as a replacement for relational transactions. It stores `activity_logs` and `notifications`, where flexible document records and append-only writes are appropriate. The core business state remains in MySQL.

## Local setup

### Requirements

- Node.js 18.17+ (Node 20 LTS recommended)
- MySQL 8.0+
- MongoDB 6+ (local Community Server or MongoDB Atlas)

### 1. Configure databases

Create the MySQL schema and advanced objects:

```bash
mysql -u root -p < database/schema.sql
```

Copy the environment template and set credentials:

```bash
cp .env.example .env.local
```

Set `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE`, `MONGODB_URI`, `MONGODB_DATABASE`, and a long random `JWT_SECRET` (32+ characters). For Atlas, use the MongoDB connection string supplied by Atlas.

### 2. Install and run

```bash
npm install
npm run dev
```

Open http://localhost:3000.

### 3. Optional demo data

```bash
node database/seed.mjs
```

Demo accounts (only created by the optional seed script):

- Organizer: `organizer@feastlink.demo` / `FeastLink@123`
- Shelter: `shelter@feastlink.demo` / `FeastLink@123`

Change these credentials and never seed demo accounts into a public production database.

## Main application routes

| Route | Purpose |
|---|---|
| `/login`, `/register` | Authentication and onboarding |
| `/dashboard` | Role-aware impact overview |
| `/food` | Browse available surplus food |
| `/food/new` | Organizer food listing form |
| `/requests` | Shelter requests and organizer approvals |
| `/deliveries` | Pickup, transit and delivery status |
| `/history` | Donation records and impact totals |

## API routes

- `POST /api/auth/register`, `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/auth/me`
- `GET/POST /api/food`
- `GET/POST /api/requests`, `POST/PATCH /api/requests/:id/approve`
- `GET/PATCH /api/deliveries`
- `GET/POST /api/history`
- `GET /api/dashboard`

All protected APIs verify the session and enforce role permissions server-side. Passwords are never returned by the API.

## Deployment

### Vercel (recommended for the Next.js frontend/API)

1. Push this repository to GitHub.
2. Import the repository in Vercel.
3. Add the environment variables from `.env.example` in Project Settings → Environment Variables.
4. Provision MySQL on a managed provider that supports MySQL 8 (for example, Aiven, Railway, or AWS RDS) and MongoDB Atlas; allow the Vercel deployment to connect to both.
5. Run `database/schema.sql` once against the production MySQL instance using a secure SQL client. Do not run schema creation on every application request.
6. Deploy. Vercel runs `npm run build` and `npm start` is managed by the platform.

For a traditional Node host, run `npm install`, `npm run build`, then `npm start` with the same environment variables and a reverse proxy/HTTPS in front.

## Important production hardening

- Use managed database TLS, network allowlists/private networking and least-privilege DB users.
- Replace the development JWT secret; rotate it if exposed.
- Configure backups and retention for both databases.
- Add rate limiting, email verification, password reset and CSRF/origin protections before public launch.
- Add an explicit food-safety checklist and moderation process before allowing public listings. The app currently captures prepared and expiry times but does not certify food safety.
- MongoDB logging is best-effort; core transactional state and permissions do not depend on MongoDB being online.

## Notes

The app requires reachable MySQL and MongoDB instances and valid environment variables to operate fully. The source bundle is deployable, but it is not automatically hosted or connected to your cloud database by this download.

## Project verification checklist

Use this checklist when setting up FEASTLINK locally or preparing a demo.

### Environment and startup
- [ ] Configure `.env.local` using `.env.example`.
- [ ] Confirm MySQL and MongoDB are reachable.
- [ ] Apply `database/schema.sql` to the MySQL database.
- [ ] Install dependencies with `npm install`.
- [ ] Start the application with `npm run dev`.

### Core workflows
- [ ] Register and log in as an Organizer.
- [ ] Create a surplus-food listing.
- [ ] Register and log in as a Shelter Admin.
- [ ] Browse available food and submit a request.
- [ ] Verify pending requests do not reduce available meal capacity.
- [ ] Approve a request and verify allocation and delivery records are created.
- [ ] Reject a request and verify no allocation is created.
- [ ] Progress a delivery through pickup, transit, and delivered.
- [ ] Record donation history after delivery.
- [ ] Confirm dashboard and history totals reflect the completed workflow.

### Before sharing or deployment
- [ ] Ensure `.env.local` and real credentials are not committed.
- [ ] Use a strong, unique `JWT_SECRET`.
- [ ] Do not use demo credentials in production.
- [ ] Review the production-hardening recommendations above.
