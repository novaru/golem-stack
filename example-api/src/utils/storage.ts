import { Logger } from "tslog";

const log = new Logger({ prettyLogTimeZone: "local" });

/**
 * Utility functions for managing file storage
 * Ensures the upload directory exists and calculates storage usage.
 */
export async function ensureUploadDir() {
    const uploadDir = "./uploads";
    try {
        await Bun.write(`${uploadDir}/.keep`, "");
    } catch (error) {
        log.error("Failed to create upload directory:", error);
    }
}

/**
 * Ensures the upload directory exists.
 * If it doesn't, creates the directory and a .keep file to maintain its existence.
 * @returns `{Promise<void>}`
 * @throws {Error} If the directory creation fails.
 */
export async function getStorageUsage(): Promise<number> {
    try {
        const uploadDir = "./uploads";
        if (!(await Bun.file(uploadDir).exists())) return 0;

        const files = new Bun.Glob("*").scan({ cwd: uploadDir });
        let totalSize = 0;

        for await (const filename of files) {
            const file = Bun.file(`${uploadDir}/${filename}`);
            if (await file.exists()) {
                totalSize += file.size;
            }
        }

        return totalSize;
    } catch (error) {
        log.error("Failed to calculate storage usage:", error);
        return 0;
    }
}
