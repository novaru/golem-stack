import { MiddlewareHandler, Context } from "hono";
import { Counter, Histogram, Gauge, Registry } from "prom-client";

const registry = new Registry();

// HTTP request counter
const httpRequestCounter = new Counter({
    name: "http_requests_total",
    help: "Total number of HTTP requests",
    labelNames: ["method", "route", "status_code"],
});
registry.registerMetric(httpRequestCounter);

// HTTP request duration histogram
const httpRequestDuration = new Histogram({
    name: "http_request_duration_seconds",
    help: "Duration of HTTP requests in seconds",
    labelNames: ["method", "route", "status_code"],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5],
});
registry.registerMetric(httpRequestDuration);

/**
 * Prometheus middleware for Hono
 * Collects HTTP request metrics: method, route, status code, and duration.
 */
export const prometheusMiddleware = (): MiddlewareHandler => {
    return async (c: Context, next) => {
        const start = process.hrtime();
        await next();
        const [seconds, nanoseconds] = process.hrtime(start);
        const duration = seconds + nanoseconds / 1e9;
        const method = c.req.method;
        // Use route pattern if available, fallback to path
        // Hono Context may not have routePath, so fallback safely
        const route = (c as any).routePath ?? c.req.path;
        const statusCode = c.res.status.toString();
        httpRequestCounter.inc({ method, route, status_code: statusCode });
        httpRequestDuration.observe(
            { method, route, status_code: statusCode },
            duration,
        );
    };
};

/**
 * Metrics handler for Prometheus scraping
 */
export const metricsHandler = async (c: Context) => {
    c.header("Content-Type", registry.contentType);
    return c.text(await registry.metrics());
};

// File operation metrics
export const fileOperationsTotal = new Counter({
    name: "file_operations_total",
    help: "Total number of file operations (upload, download, delete, list)",
    labelNames: ["operation", "status"],
});
registry.registerMetric(fileOperationsTotal);

export const uploadedFilesSize = new Histogram({
    name: "uploaded_files_size_bytes",
    help: "Histogram of uploaded file sizes in bytes",
    buckets: [
        1024,
        10 * 1024,
        100 * 1024,
        1024 * 1024,
        10 * 1024 * 1024,
        100 * 1024 * 1024,
    ],
});
registry.registerMetric(uploadedFilesSize);

export const currentStorageUsage = new Gauge({
    name: "storage_usage_bytes",
    help: "Current storage usage in bytes",
});
registry.registerMetric(currentStorageUsage);

export { registry };
