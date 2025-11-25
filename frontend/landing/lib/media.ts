export type MediaPresignResponse = {
  url: string;
  headers: Record<string, string>;
  method: string;
  expires_at: string;
  storage_path: string;
  storage_bucket?: string;
};

export type UploadViaPresignParams = {
  apiBaseUrl: string;
  storagePath: string;
  file: Blob | ArrayBuffer;
  contentType: string;
  accessToken?: string;
  upsert?: boolean;
  credentials?: RequestCredentials;
};

async function requestPresign(
  params: UploadViaPresignParams
): Promise<MediaPresignResponse> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  if (params.accessToken) {
    headers['Authorization'] = `Bearer ${params.accessToken}`;
  }

  const response = await fetch(`${params.apiBaseUrl}/media/presign`, {
    method: 'POST',
    headers,
    credentials: params.credentials ?? 'include',
    body: JSON.stringify({
      intent: 'upload',
      storage_path: params.storagePath,
      content_type: params.contentType,
      upsert: params.upsert ?? false,
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`Presign failed: ${response.status} ${detail}`);
  }

  return (await response.json()) as MediaPresignResponse;
}

export async function uploadViaPresignedUrl(
  params: UploadViaPresignParams
): Promise<MediaPresignResponse> {
  const presign = await requestPresign(params);
  await uploadWithPresignedUrl(presign, params.file);
  return presign;
}

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
