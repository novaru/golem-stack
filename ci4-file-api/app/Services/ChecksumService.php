<?php

namespace App\Services;

class ChecksumService
{
    /**
     * Calculate SHA-256 checksum of a file
     *
     * @param string $filePath Path to the file
     * @return string SHA-256 hash
     */
    public static function calculate(string $filePath): string
    {
        return hash_file('sha256', $filePath);
    }

    /**
     * Calculate SHA-256 checksum from file contents
     *
     * @param string $contents File contents
     * @return string SHA-256 hash
     */
    public static function calculateFromContents(string $contents): string
    {
        return hash('sha256', $contents);
    }

    /**
     * Verify file checksum matches expected value
     *
     * @param string $filePath Path to the file
     * @param string $expectedChecksum Expected checksum
     * @return bool True if checksums match
     */
    public static function verify(string $filePath, string $expectedChecksum): bool
    {
        return self::calculate($filePath) === $expectedChecksum;
    }
}
