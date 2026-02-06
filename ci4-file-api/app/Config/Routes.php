<?php

use CodeIgniter\Router\RouteCollection;

/**
 * @var RouteCollection $routes
 */

// Root endpoint
$routes->get('/', 'Home::index');

// Health check
$routes->get('/health', 'HealthController::index');

// Prometheus metrics
$routes->get('/metrics', 'MetricsController::index');

// File API routes
$routes->group('api/files', function($routes) {
    // List files
    $routes->get('/', 'FileController::index');
    
    // Search files
    $routes->get('search', 'FileController::search');
    
    // Recent files
    $routes->get('recent', 'FileController::recent');
    
    // Storage stats
    $routes->get('stats', 'FileController::stats');
    
    // Upload file
    $routes->post('/', 'FileController::create');
    
    // Download file (must be after other GET routes to avoid conflicts)
    $routes->get('(:segment)', 'FileController::show/$1');
    
    // Delete file
    $routes->delete('(:segment)', 'FileController::delete/$1');
});

