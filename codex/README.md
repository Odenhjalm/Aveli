+# Codex – Struktur & Arbetsflöde
+
+## Struktur
+```
+AGENT_PROMPT.md                 # Masterprompt (sanningskälla)
+.codex/
+  prompts/
+    task.feature.md             # Mall för features
+    task.fix.md                 # Mall för bugfixar
+  tasks/
+    EXAMPLES.md                 # Exempel på uppgifter
+```
+
+## Så jobbar du
+1. Skriv uppgiften i en issue-kommentar eller i chatten, referera till `AGENT_PROMPT.md`.  
+2. Be om **unified diff** (patch) eller låt workflow skapa en PR.  
+3. Granska diff → applicera → commit/push (eller automerge).
+
+## Kommandon
+Applicera patch manuellt:
+```bash
+git apply --whitespace=fix patch.diff
+git add -A
+git commit -m "AI: apply patch"
+git push
+```
+

