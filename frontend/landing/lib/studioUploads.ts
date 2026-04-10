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
  media_asset_id: string;
  asset_state: string;
  upload_url: string;
  headers: Record<string, string>;
  expires_at: string;
};

type CanonicalLessonMediaPlacement = {
  lesson_media_id: string;
  lesson_id: string;
  media_asset_id: string;
  position: number;
  media_type: 'image' | 'audio' | 'video' | 'document';
  asset_state: string;
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

  const uploadTargetUrl =
    `${params.apiBaseUrl}/api/lessons/${params.lessonId}/media-assets/upload-url`;
  const uploadTargetResponse = await fetch(uploadTargetUrl, {
    method: 'POST',
    headers,
    credentials: params.credentials ?? 'include',
    body: JSON.stringify({
      filename: params.filename,
      mime_type: params.contentType,
      size_bytes: resolveByteSize(params.file),
      media_type: mediaType,
    }),
  });
  if (!uploadTargetResponse.ok) {
    const detail = await uploadTargetResponse.text();
    throw new Error(
      `Lesson media upload-url failed: ${uploadTargetResponse.status} ${detail}`
    );
  }

  const uploadTarget =
    (await uploadTargetResponse.json()) as CanonicalLessonUploadTarget;
  const mediaAssetId = uploadTarget.media_asset_id;
  if (!mediaAssetId) {
    throw new Error('Lesson media upload-url response missing media_asset_id');
  }
  if (uploadTarget.asset_state !== 'pending_upload') {
    throw new Error('Lesson media upload-url response has invalid asset_state');
  }
  const presign: MediaPresignResponse = {
    url: uploadTarget.upload_url,
    headers: uploadTarget.headers,
    method: 'PUT',
    expires_at: uploadTarget.expires_at,
  };
  await uploadWithPresignedUrl(presign, params.file);

  const completeResponse = await fetch(
    `${params.apiBaseUrl}/api/media-assets/${mediaAssetId}/upload-completion`,
    {
      method: 'POST',
      headers,
      credentials: params.credentials ?? 'include',
      body: JSON.stringify({}),
    }
  );

  if (!completeResponse.ok) {
    const detail = await completeResponse.text();
    throw new Error(
      `Lesson media complete failed: ${completeResponse.status} ${detail}`
    );
  }

  const placementUrl =
    `${params.apiBaseUrl}/api/lessons/${params.lessonId}/media-placements`;
  const placementResponse = await fetch(placementUrl, {
    method: 'POST',
    headers,
    credentials: params.credentials ?? 'include',
    body: JSON.stringify({
      media_asset_id: mediaAssetId,
    }),
  });

  if (!placementResponse.ok) {
    const detail = await placementResponse.text();
    throw new Error(
      `Lesson media placement failed: ${placementResponse.status} ${detail}`
    );
  }

  return (await placementResponse.json()) as CanonicalLessonMediaPlacement;
}
