import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import { fileRoutes } from "./routes/files";
import { prometheusMiddleware, metricsHandler } from "./middleware/prometheus";
import { dbService } from "./services/database";

import { Logger } from "tslog";

const log = new Logger({ prettyLogTimeZone: "local" });
const app = new Hono();

// Initialize database connection
dbService.connect().catch(log.fatal);

// Graceful shutdown
process.on("SIGTERM", async () => {
    log.info("Shutting down gracefully...");
    await dbService.disconnect();
    process.exit(0);
});

process.on("SIGINT", async () => {
    log.info("Shutting down gracefully...");
    await dbService.disconnect();
    process.exit(0);
});

// Middleware
app.use("*", cors());
app.use("*", logger());
app.use("*", prometheusMiddleware());

// Health check (now includes database status)
app.get("/health", async (c) => {
    const dbHealth = await dbService.healthCheck();

    return c.json({
        status: "ok",
        timestamp: new Date().toISOString(),
        service: "file-manager-api",
        version: "1.0.0",
        instance: process.env.INSTANCE_ID || process.env.APP_NAME || "unknown",
        database: dbHealth,
    });
});

app.get("/metrics", metricsHandler);
app.route("/api/files", fileRoutes);
app.get("/", (c) => {
    return c.json({
        message: "File Manager API with PostgreSQL Sync",
        version: "1.0.0",
        instance: process.env.INSTANCE_ID || process.env.APP_NAME || "unknown",
        features: [
            "postgresql-sync",
            "prometheus-metrics",
            "file-checksum",
            "duplicate-detection",
            "search",
        ],
        endpoints: {
            health: "/health",
            metrics: "/metrics",
            files: {
                list: "GET /api/files?limit=100&offset=0",
                search: "GET /api/files/search?q=query",
                recent: "GET /api/files/recent?limit=10",
                stats: "GET /api/files/stats",
                upload: "POST /api/files",
                download: "GET /api/files/:filename",
                delete: "DELETE /api/files/:filename",
            },
        },
    });
});

const port = parseInt(process.env.PORT || "5000");

log.info(`File Manager API with PostgreSQL sync starting on port ${port}`);
log.info(`Metrics server on port ${process.env.METRICS_PORT || "9000"}`);
log.info(
    `Instance ID: ${process.env.INSTANCE_ID || process.env.APP_NAME || "unknown"}`,
);

export default {
    port,
    fetch: app.fetch,
};
