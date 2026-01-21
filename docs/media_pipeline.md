# Media pipeline note

Large media files (multi-GB audio/video) are uploaded and streamed directly
between the frontend and object storage. The backend is only a control plane:
it authenticates, validates metadata, and issues short-lived signed URLs.
This avoids backend proxying so memory usage stays constant and HTTP Range
requests work through the storage CDN.
