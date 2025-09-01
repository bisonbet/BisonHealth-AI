import {NextRequest} from "next/server";
import fs from "fs/promises";
import {join, basename} from "path";

export async function GET(
    req: NextRequest,
    {params}: { params: Promise<{ filename: string }> }
) {
    const {filename} = await params;

    // Security: Sanitize filename to prevent directory traversal attacks.
    const safeFilename = basename(filename);
    if (safeFilename !== filename || !safeFilename.match(/^[a-zA-Z0-9-_]+\.(pdf|png)$/)) {
        return new Response('Invalid filename', {status: 400});
    }

    const filePath = join(process.cwd(), 'public', 'uploads', safeFilename);

    try {
        const file = await fs.readFile(filePath);

        return new Response(new Uint8Array(file), {
            headers: {
                'Content-Type': 'application/octet-stream',
                'Content-Disposition': `attachment; filename="${safeFilename}"`
            }
        });
    } catch (error: unknown) {
        if (error && typeof error === 'object' && 'code' in error && error.code === 'ENOENT') {
            return new Response('File not found', {status: 404});
        }
        console.error(`Error reading file ${filePath}:`, error);
        return new Response('Internal Server Error', {status: 500});
    }
}
