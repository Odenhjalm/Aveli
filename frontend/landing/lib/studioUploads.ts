import { MediaPresignResponse, uploadWithPresignedUrl } from './media';

export type LessonMediaUploadParams = {
  apiBaseUrl: string;
  lessonId: string;
  file: Blob | ArrayBuffer;
  filename: string;
  contentType: string;
  mediaType?: 'image' | 'audio' | 'video' | 'document' | 'pdf';
  isIntro?: boolean;
  accessToken?: string;
  credentials?: RequestCredentials;
};

type CanonicalLessonUploadTarget = {
  media_asset_id?: string;
  media_id?: string;
  upload_url: string;
  headers: Record<string, string>;
  expires_at: string;
  storage_path: string;
};

function normalizeLessonMediaType(
  contentType: string,
  mediaType?: LessonMediaUploadParams['mediaType']
): 'image' | 'audio' | 'video' | 'document' | undefined {
  if (mediaType) {
    return mediaType === 'pdf' ? 'document' : mediaType;
  }
  const lower = contentType.trim().toLowerCase();
  if (lower.startsWith('image/')) return 'image';
  if (lower.startsWith('audio/')) return 'audio';
  if (lower.startsWith('video/')) return 'video';
  if (lower === 'application/pdf') return 'document';
  return undefined;
}

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
  const mediaType = normalizeLessonMediaType(
    params.contentType,
    params.mediaType
  );
  if (!mediaType) {
    throw new Error('Unsupported lesson media type');
  }

  const uploadTargetResponse = await fetch(
    `${params.apiBaseUrl}/api/media/upload-url`,
    {
      method: 'POST',
      headers,
      credentials: params.credentials ?? 'include',
      body: JSON.stringify({
        filename: params.filename,
        mime_type: params.contentType,
        size_bytes: resolveByteSize(params.file),
        media_type: mediaType,
        lesson_id: params.lessonId,
      }),
    }
  );
  if (!uploadTargetResponse.ok) {
    const detail = await uploadTargetResponse.text();
    throw new Error(
      `Lesson media upload-url failed: ${uploadTargetResponse.status} ${detail}`
    );
  }

  const uploadTarget =
    (await uploadTargetResponse.json()) as CanonicalLessonUploadTarget;
  const mediaId = uploadTarget.media_asset_id ?? uploadTarget.media_id;
  if (!mediaId) {
    throw new Error('Lesson media upload-url response missing media id');
  }
  const presign: MediaPresignResponse = {
    url: uploadTarget.upload_url,
    headers: uploadTarget.headers,
    method: 'PUT',
    expires_at: uploadTarget.expires_at,
    storage_path: uploadTarget.storage_path,
  };
  await uploadWithPresignedUrl(presign, params.file);

  const completeResponse = await fetch(
    `${params.apiBaseUrl}/api/media/complete`,
    {
      method: 'POST',
      headers,
      credentials: params.credentials ?? 'include',
      body: JSON.stringify({
        media_id: mediaId,
      }),
    }
  );

  if (!completeResponse.ok) {
    const detail = await completeResponse.text();
    throw new Error(
      `Lesson media complete failed: ${completeResponse.status} ${detail}`
    );
  }

  const attachResponse = await fetch(`${params.apiBaseUrl}/api/media/attach`, {
    method: 'POST',
    headers,
    credentials: params.credentials ?? 'include',
    body: JSON.stringify({
      media_id: mediaId,
      link_scope: 'lesson',
      lesson_id: params.lessonId,
    }),
  });

  if (!attachResponse.ok) {
    const detail = await attachResponse.text();
    throw new Error(
      `Lesson media attach failed: ${attachResponse.status} ${detail}`
    );
  }

  const attached = (await attachResponse.json()) as Record<string, unknown> & {
    lesson_media?: Record<string, unknown>;
  };
  return attached.lesson_media ?? attached;
}
