import uuid
import json
import asyncio
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Tuple, Any
import httpx
import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from sqlalchemy import create_engine, Column, String, Text, DateTime, Float, JSON, UUID as SQLUUID
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from sqlalchemy.sql import func
from sqlalchemy.exc import SQLAlchemyError
from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_similarity

# --- Models and Setup ---
Base = declarative_base()

class Session(Base):
    __tablename__ = "sessions"
    id = Column(SQLUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    task_type = Column(String, nullable=True)

class Interaction(Base):
    __tablename__ = "interactions"
    id = Column(SQLUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id = Column(SQLUUID(as_uuid=True), nullable=False)
    prompt = Column(Text, nullable=False)
    response = Column(Text, nullable=False)
    model = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    score = Column(Float, nullable=True)
    embedding = Column(ARRAY(Float), nullable=True)
    task_type = Column(String, nullable=True)

class Leaderboard(Base):
    __tablename__ = "leaderboard"
    id = Column(SQLUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    model = Column(String, nullable=False)
    task_type = Column(String, nullable=True)
    avg_score = Column(Float, nullable=False)
    interaction_count = Column(Integer, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow)

# --- Pydantic Models ---
class SessionCreate(BaseModel):
    task_type: Optional[str] = None

class SessionResponse(BaseModel):
    session_id: uuid.UUID
    created_at: datetime
    task_type: Optional[str]

class InteractionCreate(BaseModel):
    session_id: uuid.UUID
    prompt: str
    response: str
    model: str
    task_type: Optional[str] = None

class InteractionResponse(BaseModel):
    id: uuid.UUID
    session_id: uuid.UUID
    prompt: str
    response: str
    model: str
    created_at: datetime
    score: Optional[float]
    task_type: Optional[str]

class SearchRequest(BaseModel):
    query: str
    limit: int = 5

class SearchResult(BaseModel):
    id: uuid.UUID
    session_id: uuid.UUID
    prompt: str
    response: str
    model: str
    created_at: datetime
    score: Optional[float]
    similarity: float
    task_type: Optional[str]

class LeaderboardEntry(BaseModel):
    model: str
    task_type: Optional[str]
    avg_score: float
    interaction_count: int
    updated_at: datetime

# --- Core Classes ---
class SessionManager:
    def __init__(self, db_session):
        self.db = db_session

    def create_session(self, task_type: Optional[str] = None) -> Session:
        session = Session(task_type=task_type)
        self.db.add(session)
        self.db.commit()
        self.db.refresh(session)
        return session

    def get_session(self, session_id: uuid.UUID) -> Optional[Session]:
        return self.db.query(Session).filter(Session.id == session_id).first()

    def get_session_history(self, session_id: uuid.UUID) -> List[Interaction]:
        return (
            self.db.query(Interaction)
            .filter(Interaction.session_id == session_id)
            .order_by(Interaction.created_at.asc())
            .all()
        )

class MemoryStore:
    def __init__(self, db_session, embedding_model: str = "nomic-embed-text"):
        self.db = db_session
        self.embedding_model = embedding_model
        self.client = httpx.AsyncClient(base_url="http://localhost:11434")

    async def embed_text(self, text: str) -> List[float]:
        try:
            response = await self.client.post(
                "/api/embeddings",
                json={"model": self.embedding_model, "prompt": text},
            )
            response.raise_for_status()
            return response.json()["embedding"]
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Embedding failed: {e}")

    async def store_interaction(
        self,
        session_id: uuid.UUID,
        prompt: str,
        response: str,
        model: str,
        task_type: Optional[str] = None,
    ) -> Interaction:
        embedding = await self.embed_text(prompt)
        interaction = Interaction(
            session_id=session_id,
            prompt=prompt,
            response=response,
            model=model,
            embedding=embedding,
            task_type=task_type,
        )
        self.db.add(interaction)
        self.db.commit()
        self.db.refresh(interaction)
        return interaction

    async def score_response(self, response: str) -> float:
        # Simple scoring: length, structure, keyword presence
        length_score = min(len(response.split()) / 100, 1.0)
        structure_score = 0.5 if "\n" in response else 0.2
        keyword_score = 0.3 if ("summary" in response.lower() or "conclusion" in response.lower()) else 0.1
        return (length_score + structure_score + keyword_score) / 3

    async def update_interaction_score(self, interaction_id: uuid.UUID) -> None:
        interaction = self.db.query(Interaction).filter(Interaction.id == interaction_id).first()
        if interaction:
            score = await self.score_response(interaction.response)
            interaction.score = score
            self.db.commit()

    async def recall(self, query: str, limit: int = 5) -> List[Tuple[Interaction, float]]:
        query_embedding = await self.embed_text(query)
        interactions = self.db.query(Interaction).filter(Interaction.embedding.isnot(None)).all()
        if not interactions:
            return []

        # Calculate similarities
        similarities = []
        for interaction in interactions:
            sim = cosine_similarity([query_embedding], [interaction.embedding])[0][0]
            similarities.append((interaction, sim))

        # Sort by similarity and decay (older interactions weighted less)
        now = datetime.utcnow()
        weighted = []
        for interaction, sim in similarities:
            age_hours = (now - interaction.created_at).total_seconds() / 3600
            decay = 1.0 / (1.0 + age_hours)  # Halve weight every hour
            weighted.append((interaction, sim * decay))

        weighted.sort(key=lambda x: x[1], reverse=True)
        return weighted[:limit]

    def get_leaderboard(self) -> List[Leaderboard]:
        return self.db.query(Leaderboard).order_by(Leaderboard.avg_score.desc()).all()

    def update_leaderboard(self) -> None:
        # Group by model and task_type, calculate avg score
        results = (
            self.db.query(
                Interaction.model,
                Interaction.task_type,
                func.avg(Interaction.score).label("avg_score"),
                func.count(Interaction.id).label("interaction_count"),
            )
            .filter(Interaction.score.isnot(None))
            .group_by(Interaction.model, Interaction.task_type)
            .all()
        )

        for model, task_type, avg_score, interaction_count in results:
            entry = (
                self.db.query(Leaderboard)
                .filter(Leaderboard.model == model, Leaderboard.task_type == task_type)
                .first()
            )
            if entry:
                entry.avg_score = avg_score
                entry.interaction_count = interaction_count
                entry.updated_at = datetime.utcnow()
            else:
                entry = Leaderboard(
                    model=model,
                    task_type=task_type,
                    avg_score=avg_score,
                    interaction_count=interaction_count,
                )
                self.db.add(entry)
        self.db.commit()

# --- FastAPI App ---
app = FastAPI()

# Initialize DB
DATABASE_URL = "postgresql://user:password@localhost:5432/ark95x"
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base.metadata.create_all(bind=engine)

# Dependency
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# --- Endpoints ---
@app.post("/api/session/new", response_model=SessionResponse)
async def new_session(task_type: Optional[str] = None, db: SessionLocal = Depends(get_db)):
    manager = SessionManager(db)
    session = manager.create_session(task_type)
    return SessionResponse(
        session_id=session.id,
        created_at=session.created_at,
        task_type=session.task_type,
    )

@app.get("/api/session/history/{session_id}", response_model=List[InteractionResponse])
async def session_history(session_id: uuid.UUID, db: SessionLocal = Depends(get_db)):
    manager = SessionManager(db)
    history = manager.get_session_history(session_id)
    return [
        InteractionResponse(
            id=i.id,
            session_id=i.session_id,
            prompt=i.prompt,
            response=i.response,
            model=i.model,
            created_at=i.created_at,
            score=i.score,
            task_type=i.task_type,
        )
        for i in history
    ]

@app.post("/api/memory/search", response_model=List[SearchResult])
async def memory_search(request: SearchRequest, db: SessionLocal = Depends(get_db)):
    store = MemoryStore(db)
    results = await store.recall(request.query, request.limit)
    return [
        SearchResult(
            id=i.id,
            session_id=i.session_id,
            prompt=i.prompt,
            response=i.response,
            model=i.model,
            created_at=i.created_at,
            score=i.score,
            similarity=sim,
            task_type=i.task_type,
        )
        for i, sim in results
    ]

@app.get("/api/leaderboard", response_model=List[LeaderboardEntry])
async def leaderboard(db: SessionLocal = Depends(get_db)):
    store = MemoryStore(db)
    store.update_leaderboard()
    entries = store.get_leaderboard()
    return [
        LeaderboardEntry(
            model=e.model,
            task_type=e.task_type,
            avg_score=e.avg_score,
            interaction_count=e.interaction_count,
            updated_at=e.updated_at,
        )
        for e in entries
    ]

@app.post("/api/interaction", response_model=InteractionResponse)
async def add_interaction(
    interaction: InteractionCreate,
    db: SessionLocal = Depends(get_db),
):
    store = MemoryStore(db)
    i = await store.store_interaction(
        interaction.session_id,
        interaction.prompt,
        interaction.response,
        interaction.model,
        interaction.task_type,
    )
    await store.update_interaction_score(i.id)
    return InteractionResponse(
        id=i.id,
        session_id=i.session_id,
        prompt=i.prompt,
        response=i.response,
        model=i.model,
        created_at=i.created_at,
        score=i.score,
        task_type=i.task_type,
    )

# --- Export ---
@app.get("/api/export/session/{session_id}")
async def export_session(session_id: uuid.UUID, db: SessionLocal = Depends(get_db)):
    manager = SessionManager(db)
    history = manager.get_session_history(session_id)
    return {
        "session_id": session_id,
        "history": [
            {
                "id": i.id,
                "prompt": i.prompt,
                "response": i.response,
                "model": i.model,
                "created_at": i.created_at.isoformat(),
                "score": i.score,
                "task_type": i.task_type,
            }
            for i in history
        ],
    }

@app.get("/api/export/leaderboard")
async def export_leaderboard(db: SessionLocal = Depends(get_db)):
    store = MemoryStore(db)
    store.update_leaderboard()
    entries = store.get_leaderboard()
    return {
        "leaderboard": [
            {
                "model": e.model,
                "task_type": e.task_type,
                "avg_score": e.avg_score,
                "interaction_count": e.interaction_count,
                "updated_at": e.updated_at.isoformat(),
            }
            for e in entries
        ]
    }

# --- Main ---
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)