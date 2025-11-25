import { describe, it, expect, vi, afterEach } from 'vitest';

import { uploadLessonMedia } from '../lib/studioUploads';

describe('uploadLessonMedia', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('performs presign, upload and completion', async () => {
    const presignPayload = {
      url: 'https://storage.test/upload',
      method: 'PUT',
      headers: { 'x-upsert': 'true' },
      expires_at: new Date().toISOString(),
      storage_path: 'course-media/course/lesson/file.mp4',
      storage_bucket: 'course-media',
    };

    const responses = [
      new Response(JSON.stringify(presignPayload), { status: 200 }),
      new Response(null, { status: 200 }),
      new Response(JSON.stringify({ id: 'media-1' }), { status: 200 }),
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

    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(fetchMock.mock.calls[0]?.[0]).toContain('/media/presign');
    expect(fetchMock.mock.calls[2]?.[0]).toContain('/media/complete');
    expect(result).toEqual({ id: 'media-1' });
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
    ).rejects.toThrow(/Lesson media presign failed/);
  });
});
