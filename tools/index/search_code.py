#!/usr/bin/env python3

import sys
from sentence_transformers import SentenceTransformer
import chromadb

query = " ".join(sys.argv[1:])

client = chromadb.Client()
collection = client.get_collection("aveli_repo")

model = SentenceTransformer("all-MiniLM-L6-v2")

embedding = model.encode([query]).tolist()

results = collection.query(
    query_embeddings=embedding,
    n_results=10
)

for doc, meta in zip(results["documents"][0], results["metadatas"][0]):
    print("\nFILE:", meta["file"])
    print(doc[:400])
