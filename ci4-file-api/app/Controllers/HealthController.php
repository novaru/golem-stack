<?php

namespace App\Controllers;

use CodeIgniter\RESTful\ResourceController;

class HealthController extends ResourceController
{
    protected $format = 'json';

    /**
     * Health check endpoint (GET /health)
     */
    public function index()
    {
        try {
            // Test database connection
            $db = \Config\Database::connect();
            $dbHealth = ['status' => 'disconnected'];
            
            try {
                $query = $db->query('SELECT NOW() as current_time, version() as pg_version');
                $result = $query->getRow();
                
                $start = microtime(true);
                $db->query('SELECT 1');
                $latency = round((microtime(true) - $start) * 1000, 2);
                
                $dbHealth = [
                    'status' => 'connected',
                    'latency' => $latency . 'ms',
                    'version' => $result->pg_version ?? 'unknown',
                    'currentTime' => $result->current_time ?? null,
                    'instance' => getenv('INSTANCE_ID') ?: getenv('APP_NAME') ?: 'unknown',
                ];
            } catch (\Exception $e) {
                $dbHealth = [
                    'status' => 'error',
                    'error' => $e->getMessage(),
                ];
            }

            return $this->respond([
                'status' => 'ok',
                'timestamp' => date('c'), // ISO 8601 format
                'service' => 'file-manager-api',
                'version' => '1.0.0',
                'instance' => getenv('INSTANCE_ID') ?: getenv('APP_NAME') ?: 'unknown',
                'database' => $dbHealth,
            ]);
        } catch (\Exception $e) {
            log_message('error', 'Health check error: ' . $e->getMessage());
            return $this->fail('Health check failed', 500);
        }
    }
}
