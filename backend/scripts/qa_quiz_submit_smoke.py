#!/usr/bin/env python3
"""Smoke test for quiz submit + certificate flow."""
from __future__ import annotations

import argparse
import os
import sys
import uuid

import httpx
import psycopg

DEFAULT_BASE_URL = "http://127.0.0.1:8080"


def resolve_base_url(cli_value: str | None = None) -> str:
    if cli_value:
        return cli_value
    return os.environ.get("QA_BASE_URL") or os.environ.get("API_BASE_URL") or DEFAULT_BASE_URL


def _ensure_db_url(url: str | None) -> str:
    if not url:
        raise SystemExit("SUPABASE_DB_URL is missing")
    if "sslmode=" in url:
        return url
    if "localhost" in url or "127.0.0.1" in url:
        return url
    sep = "&" if "?" in url else "?"
    return f"{url}{sep}sslmode=require"


def _register(client: httpx.Client, email: str, password: str, display_name: str) -> None:
    resp = client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": display_name},
    )
    if resp.status_code == 201:
        return
    if resp.status_code == 400:
        # Allow reruns if the user already exists.
        return
    resp.raise_for_status()


def _login(client: httpx.Client, email: str, password: str) -> str:
    resp = client.post("/auth/login", json={"email": email, "password": password})
    resp.raise_for_status()
    token = resp.json().get("access_token")
    if not token:
        raise RuntimeError("login did not return access_token")
    return token


def _fetch_user_id(conn: psycopg.Connection, email: str) -> str | None:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id FROM auth.users WHERE lower(email) = lower(%s) LIMIT 1",
            (email,),
        )
        row = cur.fetchone()
        return str(row[0]) if row else None


def _set_teacher_role(conn: psycopg.Connection, user_id: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE app.profiles SET role_v2 = 'teacher', updated_at = now() WHERE user_id = %s",
            (user_id,),
        )
    conn.commit()


def _cleanup(
    conn: psycopg.Connection,
    *,
    course_id: str | None,
    quiz_id: str | None,
    question_id: str | None,
    cert_id: str | None,
    teacher_id: str | None,
    student_id: str | None,
    teacher_email: str,
    student_email: str,
) -> None:
    with conn.cursor() as cur:
        if cert_id:
            cur.execute("DELETE FROM app.certificates WHERE id = %s", (cert_id,))
        if question_id:
            cur.execute("DELETE FROM app.quiz_questions WHERE id = %s", (question_id,))
        if quiz_id:
            cur.execute("DELETE FROM app.course_quizzes WHERE id = %s", (quiz_id,))
        if course_id:
            cur.execute("DELETE FROM app.courses WHERE id = %s", (course_id,))
        for user_id, email in ((teacher_id, teacher_email), (student_id, student_email)):
            if user_id:
                cur.execute("DELETE FROM app.refresh_tokens WHERE user_id = %s", (user_id,))
                cur.execute("DELETE FROM app.auth_events WHERE user_id = %s", (user_id,))
                cur.execute("DELETE FROM app.profiles WHERE user_id = %s", (user_id,))
                cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            else:
                cur.execute("DELETE FROM app.profiles WHERE lower(email) = lower(%s)", (email,))
                cur.execute("DELETE FROM auth.users WHERE lower(email) = lower(%s)", (email,))
        conn.commit()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", help="Override base URL for the backend")
    parser.add_argument("--db-url", help="Override database URL (defaults to SUPABASE_DB_URL)")
    parser.add_argument("--keep-data", action="store_true", help="Skip cleanup")
    args = parser.parse_args()

    base_url = resolve_base_url(args.base_url).rstrip("/")
    db_url = _ensure_db_url(args.db_url or os.environ.get("SUPABASE_DB_URL"))
    print(f"[config] base URL: {base_url}")

    teacher_email = f"qa_teacher_{uuid.uuid4().hex[:8]}@aveli.local"
    student_email = f"qa_student_{uuid.uuid4().hex[:8]}@aveli.local"
    password = "Secret123!"

    course_id = None
    quiz_id = None
    question_id = None
    cert_id = None
    teacher_id = None
    student_id = None

    with psycopg.connect(db_url) as conn:
        try:
            with httpx.Client(base_url=base_url, timeout=20) as client:
                health = client.get("/healthz")
                health.raise_for_status()

                _register(client, teacher_email, password, "QA Teacher")
                teacher_id = _fetch_user_id(conn, teacher_email)
                if not teacher_id:
                    raise RuntimeError("teacher user id not found")
                _set_teacher_role(conn, teacher_id)
                teacher_token = _login(client, teacher_email, password)
                teacher_headers = {"Authorization": f"Bearer {teacher_token}"}

                _register(client, student_email, password, "QA Student")
                student_id = _fetch_user_id(conn, student_email)
                if not student_id:
                    raise RuntimeError("student user id not found")
                student_token = _login(client, student_email, password)
                student_headers = {"Authorization": f"Bearer {student_token}"}

                course_title = f"Quiz Test {uuid.uuid4().hex[:6]}"
                slug = f"quiz-test-{uuid.uuid4().hex[:8]}"
                course_resp = client.post(
                    "/studio/courses",
                    headers=teacher_headers,
                    json={
                        "title": course_title,
                        "slug": slug,
                        "description": "QA course for quiz submit",
                        "is_published": True,
                    },
                )
                course_resp.raise_for_status()
                course = course_resp.json()
                course_id = course.get("id")
                if not course_id:
                    raise RuntimeError("course id missing")

                quiz_resp = client.post(
                    f"/studio/courses/{course_id}/quiz",
                    headers=teacher_headers,
                )
                quiz_resp.raise_for_status()
                quiz_payload = quiz_resp.json()
                quiz = quiz_payload.get("quiz") or quiz_payload
                quiz_id = quiz.get("id")
                if not quiz_id:
                    raise RuntimeError("quiz id missing")

                question_resp = client.post(
                    f"/studio/quizzes/{quiz_id}/questions",
                    headers=teacher_headers,
                    json={
                        "position": 0,
                        "kind": "single",
                        "prompt": "2+2?",
                        "options": {
                            "choices": [
                                {"id": 0, "label": "4"},
                                {"id": 1, "label": "5"},
                            ]
                        },
                        "correct": "0",
                    },
                )
                question_resp.raise_for_status()
                question = question_resp.json()
                question_id = question.get("id")
                if not question_id:
                    raise RuntimeError("question id missing")

                submit_resp = client.post(
                    f"/courses/quiz/{quiz_id}/submit",
                    headers=student_headers,
                    json={"answers": {question_id: 0}},
                )
                submit_resp.raise_for_status()
                result = submit_resp.json()
                passed = result.get("passed")
                score = result.get("score")
                cert_id = result.get("certificate_id")

                if passed is not True or score != "100%":
                    raise RuntimeError(f"unexpected grading result: passed={passed} score={score}")
                if not cert_id:
                    raise RuntimeError("certificate_id missing")

                cert_resp = client.get(
                    f"/profiles/{student_id}/certificates",
                    headers=student_headers,
                )
                cert_resp.raise_for_status()
                items = cert_resp.json().get("items") or []
                match = next((item for item in items if item.get("id") == cert_id), None)
                if not match:
                    raise RuntimeError("certificate not found in profile list")
                if match.get("status") != "verified" or match.get("title") != course_title:
                    raise RuntimeError(
                        f"certificate mismatch: title={match.get('title')} status={match.get('status')}"
                    )

                print(
                    "API quiz submit ok: passed=%s score=%s cert=%s"
                    % (passed, score, match.get("status"))
                )
        finally:
            if not args.keep_data:
                try:
                    _cleanup(
                        conn,
                        course_id=course_id,
                        quiz_id=quiz_id,
                        question_id=question_id,
                        cert_id=cert_id,
                        teacher_id=teacher_id,
                        student_id=student_id,
                        teacher_email=teacher_email,
                        student_email=student_email,
                    )
                except Exception as exc:  # noqa: BLE001
                    print(f"[cleanup] warning: {exc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
