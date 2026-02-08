export type MediaPresignResponse = {
  url: string;
  headers: Record<string, string>;
  method: string;
  expires_at: string;
  storage_path: string;
  storage_bucket?: string;
};

export async function uploadWithPresignedUrl(
  presign: MediaPresignResponse,
  file: Blob | ArrayBuffer
): Promise<void> {
  if (presign.method.toUpperCase() !== 'PUT') {
    throw new Error(`Unexpected method for upload: ${presign.method}`);
  }

  const uploadResponse = await fetch(presign.url, {
    method: 'PUT',
    headers: presign.headers,
    body: file,
  });

  if (!uploadResponse.ok) {
    const detail = await uploadResponse.text();
    throw new Error(`Upload failed: ${uploadResponse.status} ${detail}`);
  }
}
