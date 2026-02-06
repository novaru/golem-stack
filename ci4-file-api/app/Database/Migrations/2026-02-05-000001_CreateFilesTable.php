<?php

namespace App\Database\Migrations;

use CodeIgniter\Database\Migration;

class CreateFilesTable extends Migration
{
    public function up()
    {
        // Create files table
        $this->forge->addField([
            'id' => [
                'type'       => 'UUID',
                'null'       => false,
            ],
            'filename' => [
                'type'       => 'VARCHAR',
                'constraint' => '255',
                'null'       => false,
                'unique'     => true,
            ],
            'original_name' => [
                'type'       => 'VARCHAR',
                'constraint' => '255',
                'null'       => false,
            ],
            'size' => [
                'type'       => 'BIGINT',
                'null'       => false,
            ],
            'mime_type' => [
                'type'       => 'VARCHAR',
                'constraint' => '100',
                'null'       => false,
            ],
            'checksum' => [
                'type'       => 'VARCHAR',
                'constraint' => '64',
                'null'       => false,
            ],
            'uploaded_at' => [
                'type' => 'TIMESTAMP',
                'null' => false,
            ],
            'uploaded_by' => [
                'type'       => 'VARCHAR',
                'constraint' => '100',
                'default'    => 'api-user',
            ],
            'uploaded_instance' => [
                'type'       => 'VARCHAR',
                'constraint' => '50',
                'null'       => false,
            ],
            'created_at' => [
                'type' => 'TIMESTAMP',
                'null' => false,
            ],
            'updated_at' => [
                'type' => 'TIMESTAMP',
                'null' => false,
            ],
        ]);

        // Add primary key
        $this->forge->addPrimaryKey('id');
        
        // Add CHECK constraint for size > 0 (PostgreSQL specific)
        $sql = 'ALTER TABLE files ADD CONSTRAINT check_size_positive CHECK (size > 0)';
        $this->db->query($sql);
        
        // Create table
        $this->forge->createTable('files', true);

        // Add indexes
        $this->db->query('CREATE INDEX idx_files_uploaded_at ON files(uploaded_at DESC)');
        $this->db->query('CREATE INDEX idx_files_instance ON files(uploaded_instance)');
        $this->db->query('CREATE INDEX idx_files_original_name ON files(original_name)');
        $this->db->query('CREATE INDEX idx_files_checksum ON files(checksum)');
        $this->db->query('CREATE UNIQUE INDEX idx_files_checksum_size ON files(checksum, size)');
        
        // Add default value for id using gen_random_uuid()
        $this->db->query('ALTER TABLE files ALTER COLUMN id SET DEFAULT gen_random_uuid()');
        
        // Add default NOW() for timestamps
        $this->db->query('ALTER TABLE files ALTER COLUMN uploaded_at SET DEFAULT NOW()');
        $this->db->query('ALTER TABLE files ALTER COLUMN created_at SET DEFAULT NOW()');
        $this->db->query('ALTER TABLE files ALTER COLUMN updated_at SET DEFAULT NOW()');
    }

    public function down()
    {
        $this->forge->dropTable('files', true);
    }
}
