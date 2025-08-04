import { default as postgres } from "postgres";
import { Logger } from "tslog";

const log = new Logger({ prettyLogTimeZone: "local" });

export interface FileRecord {
    id: string;
    filename: string;
    original_name: string;
    size: number;
    mime_type: string;
    checksum: string;
    uploaded_at: string;
    uploaded_by: string;
    uploaded_instance: string;
    created_at: string;
    updated_at: string;
}

export interface FileInsert {
    filename: string;
    original_name: string;
    size: number;
    mime_type: string;
    checksum: string;
    uploaded_by?: string;
    uploaded_instance: string;
}

class DatabaseService {
    private sql: postgres.Sql;
    private instanceId: string;
    private isConnected = false;

    constructor() {
        this.instanceId =
            process.env.INSTANCE_ID || process.env.APP_NAME || "unknown";

        const dbConfig = {
            host: process.env.DB_HOST || "localhost",
            port: parseInt(process.env.DB_PORT || "5432"),
            database: process.env.DB_NAME || "filemanager",
            username: process.env.DB_USER || "postgres",
            password: process.env.DB_PASSWORD || "postgres",
            max: 10, // Connection pool size
            idle_timeout: 20,
            connect_timeout: 10,
        };

        this.sql = postgres(dbConfig);
    }

    async connect() {
        try {
            await this.sql`SELECT 1`;
            this.isConnected = true;
            log.info(`Database connected for instance: ${this.instanceId}`);
            await this.runMigrations();
        } catch (error) {
            log.fatal("Failed to connect to database:", error);
            this.isConnected = false;
            throw error;
        }
    }

    async disconnect() {
        if (this.isConnected) {
            await this.sql.end();
            this.isConnected = false;
        }
    }

    private async runMigrations() {
        try {
            await this.sql`
                CREATE TABLE IF NOT EXISTS files (
                  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                  filename VARCHAR(255) NOT NULL UNIQUE,
                  original_name VARCHAR(255) NOT NULL,
                  size BIGINT NOT NULL CHECK (size > 0),
                  mime_type VARCHAR(100) NOT NULL,
                  checksum VARCHAR(64) NOT NULL,
                  uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                  uploaded_by VARCHAR(100) DEFAULT 'api-user',
                  uploaded_instance VARCHAR(50) NOT NULL,
                  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
                )
            `;

            await this
                .sql`CREATE INDEX IF NOT EXISTS idx_files_uploaded_at ON files(uploaded_at DESC)`;
            await this
                .sql`CREATE INDEX IF NOT EXISTS idx_files_instance ON files(uploaded_instance)`;
            await this
                .sql`CREATE INDEX IF NOT EXISTS idx_files_original_name ON files(original_name)`;
            await this
                .sql`CREATE INDEX IF NOT EXISTS idx_files_checksum ON files(checksum)`;
            await this
                .sql`CREATE UNIQUE INDEX IF NOT EXISTS idx_files_checksum_size ON files(checksum, size)`;

            log.info("Database migrations completed");
        } catch (error) {
            log.error("Migration failed:", error);
            throw error;
        }
    }

    // File operations with proper locking
    async insertFile(fileData: FileInsert): Promise<FileRecord | null> {
        try {
            // Use transaction with row-level locking to prevent duplicates
            const file = await this.sql.begin(async (sql) => {
                // Check for existing file by checksum and size (potential duplicate)
                const existing = await sql`
                    SELECT filename FROM files 
                    WHERE checksum = ${fileData.checksum} AND size = ${fileData.size}
                    FOR UPDATE
                `;

                if (existing.length > 0) {
                    const [existingFile] = await sql`
                        SELECT * FROM files WHERE checksum = ${fileData.checksum} AND size = ${fileData.size} LIMIT 1
                    `;
                    if (
                        existingFile &&
                        existingFile.id &&
                        existingFile.filename
                    ) {
                        return existingFile as FileRecord;
                    }

                    // if file exists, but no filename, return null
                    // should not happen with proper constraints
                    return null;
                }

                const [newFile] = await sql`
                    INSERT INTO files (
                      filename, original_name, size, mime_type, checksum, 
                      uploaded_by, uploaded_instance
                    )
                    VALUES (
                      ${fileData.filename}, ${fileData.original_name}, ${fileData.size},
                      ${fileData.mime_type}, ${fileData.checksum}, 
                      ${fileData.uploaded_by || "api-user"}, ${fileData.uploaded_instance}
                    )
                    RETURNING *
                `;
                return newFile;
            });

            return file ? (file as FileRecord) : null;
        } catch (error) {
            log.error("Error inserting file:", error);
            return null;
        }
    }

    async getFileByOriginalName(
        originalName: string,
    ): Promise<FileRecord | null> {
        try {
            const [file] = await this.sql`
                SELECT * FROM files 
                WHERE original_name = ${originalName}
                ORDER BY uploaded_at DESC
                LIMIT 1
            `;

            return (file as FileRecord) || null;
        } catch (error) {
            log.error("Error getting file by original name:", error);
            return null;
        }
    }

    async getFileByFilename(filename: string): Promise<FileRecord | null> {
        try {
            const [file] = await this.sql`
                SELECT * FROM files 
                WHERE filename = ${filename}
                LIMIT 1
            `;

            return (file as FileRecord) || null;
        } catch (error) {
            log.error("Error getting file by filename:", error);
            return null;
        }
    }

    async getAllFiles(limit = 1000, offset = 0): Promise<FileRecord[]> {
        try {
            const files = await this.sql`
                SELECT * FROM files 
                ORDER BY uploaded_at DESC
                LIMIT ${limit} OFFSET ${offset}
            `;

            return files as unknown as FileRecord[];
        } catch (error) {
            log.error("Error getting all files:", error);
            return [];
        }
    }

    async getRecentFiles(limit = 10): Promise<FileRecord[]> {
        try {
            const files = await this.sql`
                SELECT * FROM files 
                ORDER BY uploaded_at DESC
                LIMIT ${limit}
            `;

            return files as unknown as FileRecord[];
        } catch (error) {
            log.error("Error getting recent files:", error);
            return [];
        }
    }

    async deleteFile(originalName: string): Promise<boolean> {
        try {
            // Use transaction to ensure file exists before deletion
            const result = await this.sql.begin(async (sql) => {
                const [file] = await sql`
                    SELECT filename FROM files 
                    WHERE original_name = ${originalName}
                    FOR UPDATE
                `;

                if (!file) {
                    throw new Error("File not found");
                }

                const deleteResult = await sql`
                    DELETE FROM files 
                    WHERE original_name = ${originalName}
                `;

                return {
                    deleted: deleteResult.count > 0,
                    filename: file.filename,
                };
            });

            return result.deleted;
        } catch (error) {
            log.error("Error deleting file:", error);
            return false;
        }
    }

    async getStorageStats() {
        try {
            const [stats] = await this.sql`
                SELECT 
                  COUNT(*) as total_files,
                  SUM(size) as total_size,
                  AVG(size) as average_size,
                  MAX(uploaded_at) as latest_upload,
                  MIN(uploaded_at) as earliest_upload
                FROM files
            `;

            const instanceStats = await this.sql`
                SELECT 
                  uploaded_instance,
                  COUNT(*) as file_count,
                  SUM(size) as total_size
                FROM files
                GROUP BY uploaded_instance
                ORDER BY file_count DESC
            `;

            return {
                totalFiles: parseInt(stats.total_files),
                totalSize: parseInt(stats.total_size || "0"),
                averageSize: parseFloat(stats.average_size || "0"),
                latestUpload: stats.latest_upload,
                earliestUpload: stats.earliest_upload,
                instanceDistribution: instanceStats.reduce(
                    (acc, stat) => {
                        acc[stat.uploaded_instance] = {
                            files: parseInt(stat.file_count),
                            size: parseInt(stat.total_size),
                        };
                        return acc;
                    },
                    {} as Record<string, { files: number; size: number }>,
                ),
            };
        } catch (error) {
            log.error("Error getting storage stats:", error);
            return null;
        }
    }

    async searchFiles(query: string, limit = 50): Promise<FileRecord[]> {
        try {
            const files = await this.sql`
                SELECT * FROM files 
                WHERE original_name ILIKE ${"%" + query + "%"}
                  OR mime_type ILIKE ${"%" + query + "%"}
                ORDER BY uploaded_at DESC
                LIMIT ${limit}
            `;

            return files as unknown as FileRecord[];
        } catch (error) {
            log.error("Error searching files:", error);
            return [];
        }
    }

    async getFilesByInstance(instanceId: string): Promise<FileRecord[]> {
        try {
            const files = await this.sql`
                SELECT * FROM files 
                WHERE uploaded_instance = ${instanceId}
                ORDER BY uploaded_at DESC
            `;

            return files as unknown as FileRecord[];
        } catch (error) {
            log.error("Error getting files by instance:", error);
            return [];
        }
    }

    // Health check
    async healthCheck() {
        try {
            const start = Date.now();
            const [result] = await this
                .sql`SELECT NOW() as current_time, version() as pg_version`;
            const latency = Date.now() - start;

            return {
                status: "connected",
                latency: `${latency}ms`,
                version: result.pg_version,
                currentTime: result.current_time,
                instance: this.instanceId,
            };
        } catch (error) {
            return {
                status: "error",
                error: error instanceof Error ? error.message : "Unknown error",
            };
        }
    }
}

export const dbService = new DatabaseService();
