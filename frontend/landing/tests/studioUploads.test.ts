import { describe, it, expect, vi, afterEach } from 'vitest';

import { uploadLessonMedia } from '../lib/studioUploads';

describe('uploadLessonMedia', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('performs presign, upload and completion', async () => {
    const uploadTargetPayload = {
      media_id: 'media-1',
      upload_url: 'https://storage.test/upload',
      headers: { 'x-upsert': 'true' },
      expires_at: new Date().toISOString(),
      storage_path: 'courses/course-1/lessons/lesson-id/video/file.mp4',
    };

    const responses = [
      new Response(JSON.stringify(uploadTargetPayload), { status: 200 }),
      new Response(null, { status: 200 }),
      new Response(JSON.stringify({ state: 'ready' }), { status: 200 }),
      new Response(
        JSON.stringify({ lesson_media: { id: 'lesson-media-1' } }),
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
      '/api/media/upload-url'
    );
    expect(fetchMock.mock.calls[2]?.[0]).toContain(
      '/api/media/complete'
    );
    expect(fetchMock.mock.calls[3]?.[0]).toContain('/api/media/attach');
    expect(result).toEqual({ id: 'lesson-media-1' });
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
