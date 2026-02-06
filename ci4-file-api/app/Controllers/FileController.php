<?php

namespace App\Controllers;

use App\Models\FileModel;
use App\Services\PrometheusService;
use App\Services\ChecksumService;
use CodeIgniter\HTTP\ResponseInterface;
use CodeIgniter\RESTful\ResourceController;

class FileController extends ResourceController
{
    protected $modelName = 'App\Models\FileModel';
    protected $format    = 'json';
    private PrometheusService $prometheus;
    private string $uploadDir;
    private string $instanceId;
    private const MAX_FILE_SIZE = 100 * 1024 * 1024; // 100MB

    public function __construct()
    {
        $this->prometheus = PrometheusService::getInstance();
        $this->uploadDir = WRITEPATH . 'uploads/';
        $this->instanceId = getenv('INSTANCE_ID') ?: getenv('APP_NAME') ?: 'unknown';

        // Ensure upload directory exists
        if (!is_dir($this->uploadDir)) {
            mkdir($this->uploadDir, 0755, true);
        }
    }

    /**
     * List all files (GET /api/files)
     */
    public function index()
    {
        try {
            $limit  = (int)($this->request->getGet('limit') ?? 100);
            $offset = (int)($this->request->getGet('offset') ?? 0);

            $model = new FileModel();
            $files = $model->getPaginated($limit, $offset);

            $totalSize = array_reduce($files, fn($sum, $file) => $sum + $file['size'], 0);

            $this->prometheus->incrementFileOperation('list', 'success');

            return $this->respond([
                'files' => array_map(function ($file) {
                    return [
                        'id'         => $file['id'],
                        'filename'   => $file['original_name'],
                        'size'       => (int)$file['size'],
                        'type'       => $file['mime_type'],
                        'uploadedAt' => $file['uploaded_at'],
                        'uploadedBy' => $file['uploaded_by'],
                        'instance'   => $file['uploaded_instance'],
                        'checksum'   => $file['checksum'],
                    ];
                }, $files),
                'count'      => count($files),
                'totalSize'  => $totalSize,
                'pagination' => [
                    'limit'  => $limit,
                    'offset' => $offset,
                ],
            ]);
        } catch (\Exception $e) {
            $this->prometheus->incrementFileOperation('list', 'error');
            log_message('error', 'List files error: ' . $e->getMessage());
            return $this->fail('Failed to list files', 500);
        }
    }

    /**
     * Search files (GET /api/files/search?q=query)
     */
    public function search()
    {
        try {
            $query = $this->request->getGet('q');

            if (!$query) {
                return $this->fail('Search query required', 400);
            }

            $model = new FileModel();
            $files = $model->searchFiles($query);

            return $this->respond([
                'files' => array_map(function ($file) {
                    return [
                        'id'         => $file['id'],
                        'filename'   => $file['original_name'],
                        'size'       => (int)$file['size'],
                        'type'       => $file['mime_type'],
                        'uploadedAt' => $file['uploaded_at'],
                        'instance'   => $file['uploaded_instance'],
                    ];
                }, $files),
                'count' => count($files),
                'query' => $query,
            ]);
        } catch (\Exception $e) {
            log_message('error', 'Search error: ' . $e->getMessage());
            return $this->fail('Search failed', 500);
        }
    }

    /**
     * Get recent files (GET /api/files/recent?limit=10)
     */
    public function recent()
    {
        try {
            $limit = (int)($this->request->getGet('limit') ?? 10);

            $model = new FileModel();
            $files = $model->getRecent($limit);

            return $this->respond([
                'files' => array_map(function ($file) {
                    return [
                        'id'         => $file['id'],
                        'filename'   => $file['original_name'],
                        'size'       => (int)$file['size'],
                        'type'       => $file['mime_type'],
                        'uploadedAt' => $file['uploaded_at'],
                        'instance'   => $file['uploaded_instance'],
                    ];
                }, $files),
                'count' => count($files),
            ]);
        } catch (\Exception $e) {
            log_message('error', 'Recent files error: ' . $e->getMessage());
            return $this->fail('Failed to get recent files', 500);
        }
    }

    /**
     * Get storage statistics (GET /api/files/stats)
     */
    public function stats()
    {
        try {
            $model = new FileModel();
            $stats = $model->getStorageStats();

            return $this->respond($stats);
        } catch (\Exception $e) {
            log_message('error', 'Stats error: ' . $e->getMessage());
            return $this->fail('Failed to get storage stats', 500);
        }
    }

    /**
     * Upload file (POST /api/files)
     */
    public function create()
    {
        try {
            $file = $this->request->getFile('file');

            if (!$file) {
                $this->prometheus->incrementFileOperation('upload', 'error');
                return $this->fail('No file provided', 400);
            }

            // Validate file size
            if ($file->getSize() > self::MAX_FILE_SIZE) {
                $this->prometheus->incrementFileOperation('upload', 'error');
                return $this->fail('File too large (max 100MB)', 413);
            }

            // Move to temp location for checksum calculation
            $tempPath = $file->getTempName();
            $checksum = ChecksumService::calculate($tempPath);

            // Generate unique filename
            $timestamp    = time();
            $randomId     = substr(md5(uniqid()), 0, 8);
            $originalName = $file->getClientName();
            $filename     = "{$timestamp}_{$randomId}_{$originalName}";

            // Prepare file data
            $fileData = [
                'filename'          => $filename,
                'original_name'     => $originalName,
                'size'              => $file->getSize(),
                'mime_type'         => $file->getClientMimeType() ?: 'application/octet-stream',
                'checksum'          => $checksum,
                'uploaded_by'       => 'api-user',
                'uploaded_instance' => $this->instanceId,
                'uploaded_at'       => date('Y-m-d H:i:s'),
            ];

            // Insert with duplicate detection
            $model = new FileModel();
            $fileRecord = $model->insertWithDuplicateCheck($fileData);

            if (!$fileRecord) {
                $this->prometheus->incrementFileOperation('upload', 'error');
                return $this->fail('Failed to save file metadata or duplicate detected', 409);
            }

            // Check if it's a duplicate (already exists)
            $isDuplicate = $fileRecord['filename'] !== $filename;

            if (!$isDuplicate) {
                // Move file to upload directory
                $targetPath = $this->uploadDir . $filename;

                if (!$file->move($this->uploadDir, $filename)) {
                    // Failed to move file, delete from database
                    $model->deleteByOriginalName($originalName);
                    $this->prometheus->incrementFileOperation('upload', 'error');
                    return $this->fail('Failed to save file to disk', 500);
                }
            }

            $this->prometheus->incrementFileOperation('upload', 'success');
            $this->prometheus->observeUploadSize($file->getSize());

            // Update storage usage metric
            $stats = $model->getStorageStats();
            $this->prometheus->setStorageUsage($stats['totalSize']);

            return $this->respondCreated([
                'message'    => $isDuplicate ? 'Duplicate file detected' : 'File uploaded successfully',
                'id'         => $fileRecord['id'],
                'filename'   => $originalName,
                'size'       => (int)$fileRecord['size'],
                'type'       => $fileRecord['mime_type'],
                'checksum'   => $checksum,
                'uploadedAt' => $fileRecord['uploaded_at'],
                'duplicate'  => $isDuplicate,
            ]);
        } catch (\Exception $e) {
            log_message('error', 'Upload error: ' . $e->getMessage());
            $this->prometheus->incrementFileOperation('upload', 'error');
            return $this->fail('Failed to upload file', 500);
        }
    }

    /**
     * Download file (GET /api/files/:filename)
     */
    public function show($filename = null)
    {
        try {
            if (!$filename) {
                $this->prometheus->incrementFileOperation('download', 'error');
                return $this->fail('Filename required', 400);
            }

            $model = new FileModel();
            $fileRecord = $model->findByOriginalName($filename);

            if (!$fileRecord) {
                $this->prometheus->incrementFileOperation('download', 'error');
                return $this->failNotFound('File not found');
            }

            $filepath = $this->uploadDir . $fileRecord['filename'];

            if (!file_exists($filepath)) {
                $this->prometheus->incrementFileOperation('download', 'error');
                return $this->failNotFound('File not found on disk');
            }

            $this->prometheus->incrementFileOperation('download', 'success');

            // Set headers for file download
            return $this->response
                ->setHeader('Content-Type', $fileRecord['mime_type'])
                ->setHeader('Content-Disposition', 'attachment; filename="' . $fileRecord['original_name'] . '"')
                ->setHeader('Content-Length', (string)$fileRecord['size'])
                ->setHeader('X-File-ID', $fileRecord['id'])
                ->setHeader('X-File-Checksum', $fileRecord['checksum'])
                ->setHeader('X-Uploaded-At', $fileRecord['uploaded_at'])
                ->setHeader('X-Uploaded-Instance', $fileRecord['uploaded_instance'])
                ->setBody(file_get_contents($filepath));
        } catch (\Exception $e) {
            log_message('error', 'Download error: ' . $e->getMessage());
            $this->prometheus->incrementFileOperation('download', 'error');
            return $this->fail('Failed to download file', 500);
        }
    }

    /**
     * Delete file (DELETE /api/files/:filename)
     */
    public function delete($filename = null)
    {
        try {
            if (!$filename) {
                $this->prometheus->incrementFileOperation('delete', 'error');
                return $this->fail('Filename required', 400);
            }

            $model = new FileModel();
            $fileRecord = $model->findByOriginalName($filename);

            if (!$fileRecord) {
                $this->prometheus->incrementFileOperation('delete', 'error');
                return $this->failNotFound('File not found');
            }

            $filepath = $this->uploadDir . $fileRecord['filename'];

            // Delete from database
            $deleted = $model->deleteByOriginalName($filename);

            if (!$deleted) {
                $this->prometheus->incrementFileOperation('delete', 'error');
                return $this->fail('Failed to delete file metadata', 500);
            }

            // Delete from disk
            if (file_exists($filepath)) {
                @unlink($filepath);
            }

            $this->prometheus->incrementFileOperation('delete', 'success');

            // Update storage usage metric
            $stats = $model->getStorageStats();
            $this->prometheus->setStorageUsage($stats['totalSize']);

            return $this->respondDeleted([
                'message' => 'File deleted successfully',
                'filename' => $filename,
            ]);
        } catch (\Exception $e) {
            log_message('error', 'Delete error: ' . $e->getMessage());
            $this->prometheus->incrementFileOperation('delete', 'error');
            return $this->fail('Failed to delete file', 500);
        }
    }
}
