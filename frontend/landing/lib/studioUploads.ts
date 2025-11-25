import { MediaPresignResponse, uploadWithPresignedUrl } from './media';

export type LessonMediaUploadParams = {
  apiBaseUrl: string;
  lessonId: string;
  file: Blob | ArrayBuffer;
  filename: string;
  contentType: string;
  mediaType?: 'image' | 'audio' | 'video' | 'document';
  isIntro?: boolean;
  accessToken?: string;
  credentials?: RequestCredentials;
};

function buildHeaders(token?: string): Record<string, string> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }
  return headers;
}

function resolveByteSize(file: Blob | ArrayBuffer): number {
  if (typeof Blob !== 'undefined' && file instanceof Blob) {
    return file.size;
  }
  if (file instanceof ArrayBuffer) {
    return file.byteLength;
  }
  return 0;
}

export async function uploadLessonMedia(
  params: LessonMediaUploadParams
): Promise<Record<string, unknown>> {
  const headers = buildHeaders(params.accessToken);
  const presignResponse = await fetch(
    `${params.apiBaseUrl}/studio/lessons/${params.lessonId}/media/presign`,
    {
      method: 'POST',
      headers,
      credentials: params.credentials ?? 'include',
      body: JSON.stringify({
        filename: params.filename,
        content_type: params.contentType,
        media_type: params.mediaType,
        is_intro: params.isIntro ?? false,
      }),
    }
  );
  if (!presignResponse.ok) {
    const detail = await presignResponse.text();
    throw new Error(
      `Lesson media presign failed: ${presignResponse.status} ${detail}`
    );
  }

  const presign =
    (await presignResponse.json()) as MediaPresignResponse & {
      storage_bucket: string;
    };
  await uploadWithPresignedUrl(presign, params.file);

  const completeResponse = await fetch(
    `${params.apiBaseUrl}/studio/lessons/${params.lessonId}/media/complete`,
    {
      method: 'POST',
      headers,
      credentials: params.credentials ?? 'include',
      body: JSON.stringify({
        storage_path: presign.storage_path,
        storage_bucket: presign.storage_bucket,
        content_type: params.contentType,
        byte_size: resolveByteSize(params.file),
        original_name: params.filename,
        is_intro: params.isIntro ?? false,
      }),
    }
  );

  if (!completeResponse.ok) {
    const detail = await completeResponse.text();
    throw new Error(
      `Lesson media complete failed: ${completeResponse.status} ${detail}`
    );
  }

  return (await completeResponse.json()) as Record<string, unknown>;
}
