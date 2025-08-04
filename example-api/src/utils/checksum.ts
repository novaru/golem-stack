/**
 * Calculates the SHA-256 checksum of a file-like object.
 */
export async function calculateChecksum(
    file: File | Blob | Buffer | ArrayBuffer,
): Promise<string> {
    let arrayBuffer: ArrayBuffer;

    if (typeof Buffer !== "undefined" && file instanceof Buffer) {
        arrayBuffer = new Uint8Array(file).buffer;
    } else if (file instanceof ArrayBuffer) {
        arrayBuffer = file;
    } else if (typeof Blob !== "undefined" && file instanceof Blob) {
        arrayBuffer = await new Response(file).arrayBuffer();
    } else {
        throw new TypeError("Unsupported file type for checksum calculation");
    }

    const hashBuffer = await crypto.subtle.digest("SHA-256", arrayBuffer);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}
