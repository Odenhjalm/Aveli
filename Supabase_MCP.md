https://mcp.supabase.com/mcp?project_ref=wrdwpkejuzhewisnwhso&features=docs%2Caccount%2Cdebugging%2Cdatabase%2Cdevelopment%2Cfunctions%2Cbranching%2Cstorage

add this configuration to .vscode/mcp.json:
{
"mcpServers": {
"supabase": {
"type": "http",
"url": "https://mcp.supabase.com/mcp?project_ref=wrdwpkejuzhewisnwhso&features=docs%2Caccount%2Cdebugging%2Cdatabase%2Cdevelopment%2Cfunctions%2Cbranching%2Cstorage"
}
}
}

## Snabb CLI när MCP-bron saknas

Om din editor/Claude-klient ännu inte känner till servern kan du ändå prata
direkt med MCP-slutpunkten via `scripts/mcp_supabase.py`. Scriptet läser
adressen från `.vscode/mcp.json` och använder `SUPABASE_PAT` för auth.

```bash
set -a && source .env
# Lista alla verktyg (bra sanity check)
python scripts/mcp_supabase.py list-tools
# Lista tabeller i app/public-scheman
python scripts/mcp_supabase.py list-tables --schemas app public
# Kör valfri SQL mot produktionen (exemplet dumpar tabellnamn)
python scripts/mcp_supabase.py call-tool execute_sql \
  --args '{"query":"select table_schema, table_name from information_schema.tables where table_schema not in (''pg_catalog'',''information_schema'') order by 1,2 limit 20"}'
```

Argument kan även ges via `--args-file path/to/payload.json` om du vill köra
längre querys. Använd `--server <key>` eller `--token <PAT>` om du behöver override:a.
