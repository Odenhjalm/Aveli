#!/usr/bin/env python3

import sys
from sentence_transformers import SentenceTransformer
from chromadb import PersistentClient
import chromadb.errors

# ---------------------------------------------------------
# Config
# ---------------------------------------------------------

DB_PATH = ".repo_index/chroma_db"
COLLECTION_NAME = "aveli_repo"
EMBED_MODEL = "all-MiniLM-L6-v2"
TOP_K = 10

# ---------------------------------------------------------
# Input
# ---------------------------------------------------------

query = " ".join(sys.argv[1:]).strip()

if not query:
    print("ERROR: No query provided")
    sys.exit(1)

# ---------------------------------------------------------
# Initialize Chroma (PERSISTENT)
# ---------------------------------------------------------

try:
    client = PersistentClient(path=DB_PATH)
except Exception as e:
    print(f"ERROR: Failed to initialize Chroma client: {e}")
    sys.exit(1)

# ---------------------------------------------------------
# Load collection
# ---------------------------------------------------------

try:
    collection = client.get_collection(COLLECTION_NAME)
except chromadb.errors.NotFoundError:
    print(f"ERROR: Collection '{COLLECTION_NAME}' does not exist at {DB_PATH}")
    print("Hint: Run `python tools/index/build_vector_index.py` first")
    sys.exit(1)
except Exception as e:
    print(f"ERROR: Failed to load collection: {e}")
    sys.exit(1)

# ---------------------------------------------------------
# Load embedding model
# ---------------------------------------------------------

try:
    model = SentenceTransformer(EMBED_MODEL)
except Exception as e:
    print(f"ERROR: Failed to load embedding model: {e}")
    sys.exit(1)

# ---------------------------------------------------------
# Encode query
# ---------------------------------------------------------

try:
    embedding = model.encode([query], normalize_embeddings=True).tolist()
except Exception as e:
    print(f"ERROR: Failed to encode query: {e}")
    sys.exit(1)

# ---------------------------------------------------------
# Query vector DB
# ---------------------------------------------------------

try:
    results = collection.query(
        query_embeddings=embedding,
        n_results=TOP_K
    )
except Exception as e:
    print(f"ERROR: Query failed: {e}")
    sys.exit(1)

documents = results.get("documents", [[]])[0]
metadatas = results.get("metadatas", [[]])[0]

# ---------------------------------------------------------
# Output
# ---------------------------------------------------------

if not documents:
    print("No results found.")
    sys.exit(0)

for doc, meta in zip(documents, metadatas):
    file_path = meta.get("file", "UNKNOWN")
    print("\nFILE:", file_path)
    print(doc[:400])