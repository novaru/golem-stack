<?php

namespace App\Services;

use Prometheus\CollectorRegistry;
use Prometheus\Counter;
use Prometheus\Histogram;
use Prometheus\Gauge;
use Prometheus\RenderTextFormat;
use Prometheus\Storage\InMemory;

class PrometheusService
{
    private static ?PrometheusService $instance = null;
    private CollectorRegistry $registry;
    private Counter $httpRequestsTotal;
    private Histogram $httpRequestDuration;
    private Counter $fileOperationsTotal;
    private Histogram $uploadedFilesSize;
    private Gauge $storageUsageBytes;

    private function __construct()
    {
        // Use InMemory storage adapter (simplest for containerized environment)
        $this->registry = new CollectorRegistry(new InMemory());
        
        $namespace = 'ci4';

        // HTTP request counter
        $this->httpRequestsTotal = $this->registry->getOrRegisterCounter(
            $namespace,
            'http_requests_total',
            'Total number of HTTP requests',
            ['method', 'route', 'status_code']
        );

        // HTTP request duration histogram
        $this->httpRequestDuration = $this->registry->getOrRegisterHistogram(
            $namespace,
            'http_request_duration_seconds',
            'Duration of HTTP requests in seconds',
            ['method', 'route', 'status_code'],
            [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5]
        );

        // File operations counter
        $this->fileOperationsTotal = $this->registry->getOrRegisterCounter(
            $namespace,
            'file_operations_total',
            'Total number of file operations',
            ['operation', 'status']
        );

        // Uploaded file size histogram
        $this->uploadedFilesSize = $this->registry->getOrRegisterHistogram(
            $namespace,
            'uploaded_files_size_bytes',
            'Histogram of uploaded file sizes in bytes',
            [],
            [1024, 10240, 102400, 1048576, 10485760, 104857600] // 1KB, 10KB, 100KB, 1MB, 10MB, 100MB
        );

        // Storage usage gauge
        $this->storageUsageBytes = $this->registry->getOrRegisterGauge(
            $namespace,
            'storage_usage_bytes',
            'Current storage usage in bytes',
            []
        );
    }

    /**
     * Get singleton instance
     */
    public static function getInstance(): PrometheusService
    {
        if (self::$instance === null) {
            self::$instance = new PrometheusService();
        }
        return self::$instance;
    }

    /**
     * Increment HTTP request counter
     */
    public function incrementHttpRequest(string $method, string $route, int $statusCode): void
    {
        $this->httpRequestsTotal->inc([
            $method,
            $route,
            (string)$statusCode
        ]);
    }

    /**
     * Observe HTTP request duration
     */
    public function observeHttpDuration(string $method, string $route, int $statusCode, float $duration): void
    {
        $this->httpRequestDuration->observe(
            $duration,
            [$method, $route, (string)$statusCode]
        );
    }

    /**
     * Increment file operation counter
     */
    public function incrementFileOperation(string $operation, string $status): void
    {
        $this->fileOperationsTotal->inc([$operation, $status]);
    }

    /**
     * Observe uploaded file size
     */
    public function observeUploadSize(int $size): void
    {
        $this->uploadedFilesSize->observe($size);
    }

    /**
     * Set storage usage
     */
    public function setStorageUsage(int $bytes): void
    {
        $this->storageUsageBytes->set($bytes);
    }

    /**
     * Render metrics in Prometheus text format
     */
    public function renderMetrics(): string
    {
        $renderer = new RenderTextFormat();
        return $renderer->render($this->registry->getMetricFamilySamples());
    }

    /**
     * Get registry instance (for advanced usage)
     */
    public function getRegistry(): CollectorRegistry
    {
        return $this->registry;
    }
}
