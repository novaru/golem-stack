<?php

namespace App\Models;

use CodeIgniter\Model;

class FileModel extends Model
{
    protected $table            = 'files';
    protected $primaryKey       = 'id';
    protected $useAutoIncrement = false; // UUID primary key
    protected $returnType       = 'array';
    protected $useSoftDeletes   = false;
    protected $protectFields    = true;
    protected $allowedFields    = [
        'id',
        'filename',
        'original_name',
        'size',
        'mime_type',
        'checksum',
        'uploaded_at',
        'uploaded_by',
        'uploaded_instance',
    ];

    protected bool $allowEmptyInserts = false;
    protected bool $updateOnlyChanged = true;

    protected array $casts = [];
    protected array $castHandlers = [];

    // Dates
    protected $useTimestamps = true;
    protected $dateFormat    = 'datetime';
    protected $createdField  = 'created_at';
    protected $updatedField  = 'updated_at';
    protected $deletedField  = 'deleted_at';

    // Validation
    protected $validationRules      = [
        'filename'           => 'required|max_length[255]|is_unique[files.filename]',
        'original_name'      => 'required|max_length[255]',
        'size'               => 'required|integer|greater_than[0]',
        'mime_type'          => 'required|max_length[100]',
        'checksum'           => 'required|max_length[64]',
        'uploaded_instance'  => 'required|max_length[50]',
    ];
    protected $validationMessages   = [];
    protected $skipValidation       = false;
    protected $cleanValidationRules = true;

    // Callbacks
    protected $allowCallbacks = true;
    protected $beforeInsert   = [];
    protected $afterInsert    = [];
    protected $beforeUpdate   = [];
    protected $afterUpdate    = [];
    protected $beforeFind     = [];
    protected $afterFind      = [];
    protected $beforeDelete   = [];
    protected $afterDelete    = [];

    /**
     * Check if file with same checksum and size already exists (duplicate detection)
     *
     * @param string $checksum File SHA-256 checksum
     * @param int $size File size in bytes
     * @return array|null Existing file record or null if not found
     */
    public function findDuplicate(string $checksum, int $size): ?array
    {
        return $this->where('checksum', $checksum)
                    ->where('size', $size)
                    ->first();
    }

    /**
     * Insert file with duplicate detection using transaction
     *
     * @param array $data File data
     * @return array|null Inserted file record or existing duplicate, null on error
     */
    public function insertWithDuplicateCheck(array $data): ?array
    {
        $db = $this->db;
        
        // Start transaction
        $db->transStart();
        
        try {
            // Check for duplicate with row-level lock (FOR UPDATE)
            $existing = $db->table($this->table)
                ->select('*')
                ->where('checksum', $data['checksum'])
                ->where('size', $data['size'])
                ->get()
                ->getRowArray();
            
            if ($existing) {
                // Duplicate found, rollback and return existing
                $db->transRollback();
                return $existing;
            }
            
            // No duplicate, insert new file
            $inserted = $this->insert($data, true); // true = return ID
            
            if (!$inserted) {
                $db->transRollback();
                return null;
            }
            
            // Get the inserted record
            $newFile = $this->find($inserted);
            
            $db->transComplete();
            
            return $newFile ?: null;
            
        } catch (\Exception $e) {
            $db->transRollback();
            log_message('error', 'File insert error: ' . $e->getMessage());
            return null;
        }
    }

    /**
     * Get file by original name (most recent if multiple)
     */
    public function findByOriginalName(string $originalName): ?array
    {
        return $this->where('original_name', $originalName)
                    ->orderBy('uploaded_at', 'DESC')
                    ->first();
    }

    /**
     * Search files by original name or mime type
     */
    public function searchFiles(string $query, int $limit = 50): array
    {
        return $this->like('original_name', $query, 'both', null, true) // case-insensitive
                    ->orLike('mime_type', $query, 'both', null, true)
                    ->orderBy('uploaded_at', 'DESC')
                    ->limit($limit)
                    ->findAll();
    }

    /**
     * Get recent files
     */
    public function getRecent(int $limit = 10): array
    {
        return $this->orderBy('uploaded_at', 'DESC')
                    ->limit($limit)
                    ->findAll();
    }

    /**
     * Get storage statistics
     */
    public function getStorageStats(): array
    {
        $db = $this->db;
        
        // Overall stats
        $overallStats = $db->table($this->table)
            ->select('COUNT(*) as total_files, SUM(size) as total_size, AVG(size) as average_size, MAX(uploaded_at) as latest_upload, MIN(uploaded_at) as earliest_upload')
            ->get()
            ->getRowArray();
        
        // Instance distribution
        $instanceStats = $db->table($this->table)
            ->select('uploaded_instance, COUNT(*) as file_count, SUM(size) as total_size')
            ->groupBy('uploaded_instance')
            ->orderBy('file_count', 'DESC')
            ->get()
            ->getResultArray();
        
        // Build instance distribution array
        $instanceDistribution = [];
        foreach ($instanceStats as $stat) {
            $instanceDistribution[$stat['uploaded_instance']] = [
                'files' => (int)$stat['file_count'],
                'size' => (int)$stat['total_size'],
            ];
        }
        
        return [
            'totalFiles' => (int)($overallStats['total_files'] ?? 0),
            'totalSize' => (int)($overallStats['total_size'] ?? 0),
            'averageSize' => (float)($overallStats['average_size'] ?? 0),
            'latestUpload' => $overallStats['latest_upload'] ?? null,
            'earliestUpload' => $overallStats['earliest_upload'] ?? null,
            'instanceDistribution' => $instanceDistribution,
        ];
    }

    /**
     * Delete file by original name
     */
    public function deleteByOriginalName(string $originalName): bool
    {
        return $this->where('original_name', $originalName)->delete();
    }

    /**
     * Get files with pagination
     */
    public function getPaginated(int $limit = 100, int $offset = 0): array
    {
        return $this->orderBy('uploaded_at', 'DESC')
                    ->limit($limit, $offset)
                    ->findAll();
    }
}
