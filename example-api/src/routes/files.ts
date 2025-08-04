import { Hono } from "hono";
import {
    fileOperationsTotal,
    uploadedFilesSize,
    currentStorageUsage,
} from "../middleware/prometheus";
import { ensureUploadDir } from "../utils/storage";
import { dbService } from "../services/database";
import { calculateChecksum } from "../utils/checksum";
import { Logger } from "tslog";

const files = new Hono();
const log = new Logger({ prettyLogTimeZone: "local" });
const instanceId = process.env.INSTANCE_ID || process.env.APP_NAME || "unknown";

// Ensure upload directory exists
ensureUploadDir();

// List all files (from PostgreSQL)
files.get("/", async (c) => {
    try {
        const limit = parseInt(c.req.query("limit") || "100");
        const offset = parseInt(c.req.query("offset") || "0");

        const files = await dbService.getAllFiles(limit, offset);
        const totalSize = files.reduce((sum, file) => sum + file.size, 0);

        fileOperationsTotal.inc({ operation: "list", status: "success" });

        return c.json({
            files: files.map((file) => ({
                id: file.id,
                filename: file.original_name,
                size: file.size,
                type: file.mime_type,
                uploadedAt: file.uploaded_at,
                uploadedBy: file.uploaded_by,
                instance: file.uploaded_instance,
                checksum: file.checksum,
            })),
            count: files.length,
            totalSize,
            pagination: { limit, offset },
        });
    } catch (error) {
        fileOperationsTotal.inc({ operation: "list", status: "error" });
        return c.json({ error: "Failed to list files" }, 500);
    }
});

files.get("/search", async (c) => {
    try {
        const query = c.req.query("q");
        if (!query) {
            return c.json({ error: "Search query required" }, 400);
        }

        const files = await dbService.searchFiles(query);

        return c.json({
            files: files.map((file) => ({
                id: file.id,
                filename: file.original_name,
                size: file.size,
                type: file.mime_type,
                uploadedAt: file.uploaded_at,
                instance: file.uploaded_instance,
            })),
            count: files.length,
            query,
        });
    } catch (error) {
        return c.json({ error: "Search failed" }, 500);
    }
});

// Get recent files
files.get("/recent", async (c) => {
    try {
        const limit = parseInt(c.req.query("limit") || "10");
        const files = await dbService.getRecentFiles(limit);

        return c.json({
            files: files.map((file) => ({
                id: file.id,
                filename: file.original_name,
                size: file.size,
                type: file.mime_type,
                uploadedAt: file.uploaded_at,
                instance: file.uploaded_instance,
            })),
            count: files.length,
        });
    } catch (error) {
        return c.json({ error: "Failed to get recent files" }, 500);
    }
});

// Get storage statistics
files.get("/stats", async (c) => {
    try {
        const stats = await dbService.getStorageStats();
        return c.json(stats);
    } catch (error) {
        return c.json({ error: "Failed to get storage stats" }, 500);
    }
});

// Upload file
files.post("/", async (c) => {
    try {
        const formData = await c.req.formData();
        const file = formData.get("file") as File;

        if (!file) {
            fileOperationsTotal.inc({ operation: "upload", status: "error" });
            return c.json({ error: "No file provided" }, 400);
        }

        // Validate file size (max 100MB)
        const maxSize = 100 * 1024 * 1024;
        if (file.size > maxSize) {
            fileOperationsTotal.inc({ operation: "upload", status: "error" });
            return c.json({ error: "File too large (max 100MB)" }, 413);
        }

        const checksum = await calculateChecksum(file);

        // Generate unique filename
        const timestamp = Date.now();
        const randomId = Math.random().toString(36).substring(2, 8);
        const filename = `${timestamp}_${randomId}_${file.name}`;
        const filepath = `./uploads/${filename}`;

        // Try to insert into database first (with duplicate detection)
        const fileRecord = await dbService.insertFile({
            filename,
            original_name: file.name,
            size: file.size,
            mime_type: file.type || "application/octet-stream",
            checksum,
            uploaded_by: "api-user",
            uploaded_instance: instanceId,
        });

        if (!fileRecord) {
            fileOperationsTotal.inc({ operation: "upload", status: "error" });
            return c.json(
                { error: "Failed to save file metadata or duplicate detected" },
                409,
            );
        }

        try {
            await Bun.write(filepath, file);
        } catch (diskError) {
            // If disk write fails, remove from database
            await dbService.deleteFile(file.name);
            fileOperationsTotal.inc({ operation: "upload", status: "error" });
            return c.json({ error: "Failed to save file to disk" }, 500);
        }

        fileOperationsTotal.inc({ operation: "upload", status: "success" });
        uploadedFilesSize.observe(file.size);

        // Update storage usage metric
        const stats = await dbService.getStorageStats();
        if (stats) {
            currentStorageUsage.set(stats.totalSize);
        }

        return c.json(
            {
                message: "File uploaded successfully",
                id: fileRecord.id,
                filename: file.name,
                size: file.size,
                type: file.type,
                checksum,
                uploadedAt: fileRecord.uploaded_at,
            },
            201,
        );
    } catch (error) {
        log.error("Upload error:", error);
        fileOperationsTotal.inc({ operation: "upload", status: "error" });
        return c.json({ error: "Failed to upload file" }, 500);
    }
});

// Download file
files.get("/:filename", async (c) => {
    try {
        const requestedFilename = c.req.param("filename");

        const fileRecord =
            await dbService.getFileByOriginalName(requestedFilename);

        if (!fileRecord) {
            fileOperationsTotal.inc({ operation: "download", status: "error" });
            return c.json({ error: "File not found" }, 404);
        }

        const filepath = `./uploads/${fileRecord.filename}`;
        const file = Bun.file(filepath);

        if (!(await file.exists())) {
            fileOperationsTotal.inc({ operation: "download", status: "error" });
            return c.json({ error: "File not found on disk" }, 404);
        }

        fileOperationsTotal.inc({ operation: "download", status: "success" });

        return new Response(file, {
            headers: {
                "Content-Type": fileRecord.mime_type,
                "Content-Disposition": `attachment; filename="${fileRecord.original_name}"`,
                "Content-Length": fileRecord.size.toString(),
                "X-File-ID": fileRecord.id,
                "X-File-Checksum": fileRecord.checksum,
                "X-Uploaded-At": fileRecord.uploaded_at,
                "X-Uploaded-Instance": fileRecord.uploaded_instance,
            },
        });
    } catch (error) {
        log.error("Download error:", error);
        fileOperationsTotal.inc({ operation: "download", status: "error" });
        return c.json({ error: "Failed to download file" }, 500);
    }
});

// Delete file
files.delete("/:filename", async (c) => {
    try {
        const requestedFilename = c.req.param("filename");
        const fileRecord =
            await dbService.getFileByOriginalName(requestedFilename);
        if (!fileRecord) {
            fileOperationsTotal.inc({ operation: "delete", status: "error" });
            return c.json({ error: "File not found" }, 404);
        }

        const filepath = `./uploads/${fileRecord.filename}`;

        const deleted = await dbService.deleteFile(requestedFilename);

        if (!deleted) {
            fileOperationsTotal.inc({ operation: "delete", status: "error" });
            return c.json({ error: "Failed to delete file metadata" }, 500);
        }

        try {
            const proc = Bun.spawn(["rm", filepath]);
            await proc.exited;
        } catch (diskError) {
            log.error(
                "Warning: File deleted from database but not from disk:",
                diskError,
            );
        }

        fileOperationsTotal.inc({ operation: "delete", status: "success" });

        const stats = await dbService.getStorageStats();

        if (stats) {
            currentStorageUsage.set(stats.totalSize);
        }

        return c.json({
            message: "File deleted successfully",
            filename: requestedFilename,
        });
    } catch (error) {
        log.error("Delete error:", error);
        fileOperationsTotal.inc({ operation: "delete", status: "error" });
        return c.json({ error: "Failed to delete file" }, 500);
    }
});

export { files as fileRoutes };
