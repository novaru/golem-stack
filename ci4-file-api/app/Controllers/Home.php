<?php

namespace App\Controllers;

use CodeIgniter\RESTful\ResourceController;

class Home extends ResourceController
{
    protected $format = 'json';

    /**
     * API root endpoint (GET /)
     */
    public function index()
    {
        return $this->respond([
            'message' => 'File Manager API with PostgreSQL Sync',
            'version' => '1.0.0',
            'instance' => getenv('INSTANCE_ID') ?: getenv('APP_NAME') ?: 'unknown',
            'features' => [
                'postgresql-sync',
                'prometheus-metrics',
                'file-checksum',
                'duplicate-detection',
                'search',
            ],
            'endpoints' => [
                'health' => '/health',
                'metrics' => '/metrics',
                'files' => [
                    'list' => 'GET /api/files?limit=100&offset=0',
                    'search' => 'GET /api/files/search?q=query',
                    'recent' => 'GET /api/files/recent?limit=10',
                    'stats' => 'GET /api/files/stats',
                    'upload' => 'POST /api/files',
                    'download' => 'GET /api/files/:filename',
                    'delete' => 'DELETE /api/files/:filename',
                ],
            ],
        ]);
    }
}
