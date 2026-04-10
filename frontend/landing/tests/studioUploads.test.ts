import { describe, it, expect, vi, afterEach } from 'vitest';

import { uploadLessonMedia } from '../lib/studioUploads';

describe('uploadLessonMedia', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('performs canonical upload, completion and placement', async () => {
    const uploadTargetPayload = {
      media_asset_id: 'media-1',
      asset_state: 'pending_upload',
      upload_url: 'https://storage.test/upload',
      headers: { 'x-upsert': 'true' },
      expires_at: new Date().toISOString(),
    };

    const responses = [
      new Response(JSON.stringify(uploadTargetPayload), { status: 200 }),
      new Response(null, { status: 200 }),
      new Response(
        JSON.stringify({ media_asset_id: 'media-1', asset_state: 'uploaded' }),
        { status: 200 }
      ),
      new Response(
        JSON.stringify({
          lesson_media_id: 'lesson-media-1',
          lesson_id: 'lesson-id',
          media_asset_id: 'media-1',
          position: 1,
          media_type: 'video',
          asset_state: 'uploaded',
        }),
        { status: 200 }
      ),
    ];

    const fetchMock = vi.fn().mockImplementation(() => {
      const next = responses.shift();
      if (!next) {
        throw new Error('Unexpected fetch call');
      }
      return Promise.resolve(next);
    });

    global.fetch = fetchMock;

    const result = await uploadLessonMedia({
      apiBaseUrl: 'https://api.test',
      lessonId: 'lesson-id',
      file: new Uint8Array([1, 2, 3]).buffer,
      filename: 'demo.mp4',
      contentType: 'video/mp4',
      accessToken: 'token',
    });

    expect(fetchMock).toHaveBeenCalledTimes(4);
    expect(fetchMock.mock.calls[0]?.[0]).toContain(
      '/api/lessons/lesson-id/media-assets/upload-url'
    );
    expect(fetchMock.mock.calls[2]?.[0]).toContain(
      '/api/media-assets/media-1/upload-completion'
    );
    expect(fetchMock.mock.calls[3]?.[0]).toContain(
      '/api/lessons/lesson-id/media-placements'
    );
    expect(result).toEqual({
      lesson_media_id: 'lesson-media-1',
      lesson_id: 'lesson-id',
      media_asset_id: 'media-1',
      position: 1,
      media_type: 'video',
      asset_state: 'uploaded',
    });
  });

  it('throws when presign fails', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response('nope', { status: 500 })
    );
    global.fetch = fetchMock;

    await expect(
      uploadLessonMedia({
        apiBaseUrl: 'https://api.test',
        lessonId: 'lesson-id',
        file: new Uint8Array([1]).buffer,
        filename: 'demo.mp4',
        contentType: 'video/mp4',
      })
    ).rejects.toThrow(/Lesson media upload-url failed/);
  });
});
