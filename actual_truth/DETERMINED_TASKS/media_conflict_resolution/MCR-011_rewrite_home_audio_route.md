# MCR-011

- TASK_ID: `MCR-011`
- TYPE: `OWNER`
- CLUSTER: `HOME_AUDIO_ALIGNMENT`
- DESCRIPTION: `Rewrite backend/app/routes/home.py so /home/audio consumes canonical home-audio composition only and does not infer truth from legacy signing, storage, or invented runtime-media fields.`
- TARGET_FILES:
  - `backend/app/routes/home.py`
- ACTION: `rewrite`
- DEPENDS_ON:
  - `MCR-010`

