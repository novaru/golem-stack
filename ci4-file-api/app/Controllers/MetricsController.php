<?php

namespace App\Controllers;

use App\Services\PrometheusService;
use CodeIgniter\Controller;

class MetricsController extends Controller
{
    /**
     * Prometheus metrics endpoint (GET /metrics)
     */
    public function index()
    {
        try {
            $prometheus = PrometheusService::getInstance();
            $metrics = $prometheus->renderMetrics();
            
            return $this->response
                ->setHeader('Content-Type', 'text/plain; version=0.0.4')
                ->setBody($metrics);
        } catch (\Exception $e) {
            log_message('error', 'Metrics error: ' . $e->getMessage());
            return $this->response
                ->setStatusCode(500)
                ->setBody('Failed to render metrics');
        }
    }
}
