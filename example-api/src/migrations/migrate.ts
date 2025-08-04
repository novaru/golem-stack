import { readFileSync } from "fs";
import { Client } from "pg";
import { Logger } from "tslog";

const log = new Logger({ prettyLogTimeZone: "local" });

const DB_NAME = "filemanager";
const DB_USER = process.env.PGUSER || "postgres";
const DB_PASSWORD = process.env.PGPASSWORD || "postgres";
const DB_HOST = process.env.PGHOST || "localhost";
const DB_PORT = process.env.PGPORT || "5432";

async function createDatabaseIfNotExists() {
    const client = new Client({
        user: DB_USER,
        password: DB_PASSWORD,
        host: DB_HOST,
        port: parseInt(DB_PORT),
        database: "postgres", // Connect to default db to create new one
    });
    await client.connect();
    const res = await client.query(
        `SELECT 1 FROM pg_database WHERE datname = $1`,
        [DB_NAME],
    );
    if (res.rowCount === 0) {
        await client.query(`CREATE DATABASE ${DB_NAME}`);
        log.info(`Database '${DB_NAME}' created.`);
    } else {
        log.info(`Database '${DB_NAME}' already exists.`);
    }
    await client.end();
}

async function runMigration() {
    const sql = readFileSync(
        __dirname + "/../../migrations/001_create_files_table.sql",
        "utf8",
    );
    const client = new Client({
        user: DB_USER,
        password: DB_PASSWORD,
        host: DB_HOST,
        port: parseInt(DB_PORT),
        database: DB_NAME,
    });
    await client.connect();
    await client.query(sql);
    log.debug("Migration completed.");
    await client.end();
}

(async () => {
    try {
        await createDatabaseIfNotExists();
        await runMigration();
    } catch (err) {
        log.fatal("Migration failed:", err);
    }
})();
