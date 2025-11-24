+# Exempeluppgifter att ge agenten
+
+## 1) Free Tier + Access-kontroll
+```
+/agent Implementera Free Tier + RPC can_access_course():
+- RPC free_consumed_count(user_id)
+- RPC can_access_course(user_id, course_id)
+- Riverpod providers + guards i go_router
+- M3-shell + enkel CourseList med free_intro-markering
+```
+
+## 2) Lärar-Studio – grund
+```
+/agent Bygg /studio:
+- Guard: teacher/admin, annars ansökningsvy som skriver till public.teacher_requests(note)
+- CRUD: courses/modules/lessons med optimistic UI
+- Rich text bound till lessons.content (jsonb)
+- Media-upload till public-media/{user.id}/... + insert i lesson_media
+```
+
+## 3) Stripe-flöde
+```
+/agent Lägg Stripe checkout + Supabase edge webhook:
+- start_order() och complete_order()
+- PaymentSheet/Checkout i Flutter
+- Webhook sätter orders.status=paid och triggar uppdateringar
+```
+
