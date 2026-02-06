<?php

namespace App\Filters;

use App\Services\PrometheusService;
use CodeIgniter\Filters\FilterInterface;
use CodeIgniter\HTTP\RequestInterface;
use CodeIgniter\HTTP\ResponseInterface;

class PrometheusFilter implements FilterInterface
{
    private float $startTime;

    /**
     * Before request - record start time
     */
    public function before(RequestInterface $request, $arguments = null)
    {
        $this->startTime = microtime(true);
        // Allow request to continue
        return null;
    }

    /**
     * After request - record metrics
     */
    public function after(RequestInterface $request, ResponseInterface $response, $arguments = null)
    {
        try {
            $duration = microtime(true) - $this->startTime;
            $prometheus = PrometheusService::getInstance();
            
            $method = $request->getMethod();
            $route = $request->getUri()->getPath();
            $statusCode = $response->getStatusCode();
            
            // Record HTTP request metrics
            $prometheus->incrementHttpRequest($method, $route, $statusCode);
            $prometheus->observeHttpDuration($method, $route, $statusCode, $duration);
            
        } catch (\Exception $e) {
            log_message('error', 'Prometheus filter error: ' . $e->getMessage());
        }
        
        return $response;
    }
}
