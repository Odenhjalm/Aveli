# 0010D-3

- TASK_ID: `0010D-3`
- TYPE: `OWNER`
- TITLE: `Compose backend-authored cover on mounted course read surfaces`
- DEPENDS_ON:
  - `0010B`
  - `0010D-2`

## problem_statement

Mounted course routes still serialize course rows without a canonical backend-authored `cover` object, and one studio course route family skips the existing `_apply_course_read_contract()` hook entirely.

## target_state

- Public course detail reads serialize `course.cover`.
- Public course list reads serialize `cover` on each course item.
- Mounted studio course list/detail reads serialize backend-authored `cover`.
- Course cover composition happens in backend read/service authority, not in frontend code.

## verification_method

- `rg -n "response_model=schemas\\.(CourseDetailResponse|CourseListResponse|Course)" backend/app/routes`
- `rg -n "_apply_course_read_contract|read_course_detail|read_course_list|cover=" backend/app/routes backend/app/services`
- Run a targeted backend import script that instantiates mounted route response models from representative rows and confirms `cover` survives serialization.
