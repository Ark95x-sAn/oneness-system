import asyncio
import json
import logging
import os
from typing import Dict, List, Optional, Tuple

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

# ------------------------------
# Logging setup
# ------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()],
)
logger = logging.getLogger("ModelRouter")


# ------------------------------
# Pydantic models for API
# ------------------------------
class RouteRequest(BaseModel):
    prompt: str
    task_type_override: Optional[str] = None


class RouteResponse(BaseModel):
    model: str
    response: str
    logs: List[str]  # includes routing decisions and reasoning


# ------------------------------
# ModelRouter class
# ------------------------------
class ModelRouter:
    """
    Intelligent router for Ollama models on ARK95X.
    Classifies prompts, selects optimal models, handles fallbacks,
    and chains ArcX -> Amara for trading signals.
    """

    # Task type definitions
    TASK_TYPES = [
        "coding",
        "trading",
        "risk_analysis",
        "research",
        "vision",
        "general",
    ]

    # Primary and fallback models per task type
    MODEL_MAPPING = {
        "coding": {
            "primary": "codellama:34b",
            "fallback": "starcoder2:7b",
            "description": "Code generation and debugging",
        },
        "trading": {
            "primary": "arcx",
            "fallback": "mistral",  # fallback for arcx if needed
            "description": "Trading signal generation + risk validation",
            "chain": True,  # indicates special chaining with amara
        },
        "risk_analysis": {
            "primary": "amara",
            "fallback": "phi4",
            "description": "Risk validation and analysis",
        },
        "research": {
            "primary": "llama3.1:8b",
            "fallback": "phi4",
            "description": "Research and analytical tasks",
        },
        "vision": {
            "primary": "llava:13b",
            "fallback": None,
            "description": "Image understanding and vision tasks",
        },
        "general": {
            "primary": "mistral",
            "fallback": "llama3.1:8b",
            "description": "General purpose conversations",
        },
    }

    # Keyword-based classification rules
    KEYWORD_RULES = {
        "coding": [
            "code",
            "function",
            "debug",
            "implement",
            "program",
            "script",
            "algorithm",
            "syntax",
            "compile",
            "refactor",
            "class",
            "method",
            "import",
            "def ",
            "var ",
            "let ",
            "const ",
        ],
        "trading": [
            "trade",
            "buy",
            "sell",
            "signal",
            "market",
            "price",
            "volume",
            "indicator",
            "stock",
            "crypto",
            "forex",
            "position",
            "entry",
            "exit",
            "stop loss",
            "take profit",
        ],
        "risk_analysis": [
            "risk",
            "validate",
            "exposure",
            "volatility",
            "drawdown",
            "sharpe",
            "var",
            "stress test",
            "liquidity",
            "margin",
            "leverage",
            "safety",
        ],
        "research": [
            "research",
            "analyze",
            "study",
            "literature",
            "paper",
            "hypothesis",
            "experiment",
            "findings",
            "conclusion",
            "cite",
            "reference",
            "review",
        ],
        "vision": [
            "image",
            "picture",
            "vision",
            "see",
            "photo",
            "diagram",
            "chart",
            "visual",
            "camera",
            "recognize",
            "object detection",
            "face",
        ],
    }

    def __init__(self, ollama_base_url: str = "http://localhost:11434", timeout: float = 120.0):
        """
        Initialize the ModelRouter.

        Args:
            ollama_base_url: Base URL of Ollama API.
            timeout: HTTP request timeout in seconds.
        """
        self.ollama_base_url = ollama_base_url.rstrip("/")
        self.timeout = timeout
        self.client = httpx.AsyncClient(timeout=timeout)

        # Precompute embeddings for each task type using example prompts.
        # These will be loaded lazily on first classification that needs embeddings.
        self._task_embeddings: Dict[str, List[float]] = {}
        self._example_prompts = {
            "coding": "Write a Python function to sort a list.",
            "trading": "Generate a buy signal for BTC based on RSI.",
            "risk_analysis": "Calculate portfolio value at risk for 95% confidence.",
            "research": "Summarize recent advances in transformer models.",
            "vision": "Describe what is in this image.",
            "general": "Tell me a fun fact about space.",
        }

    async def close(self):
        """Close the HTTP client."""
        await self.client.aclose()

    async def _get_embeddings(self, text: str) -> List[float]:
        """
        Get embeddings for a text using nomic-embed-text model.

        Args:
            text: Input text.

        Returns:
            List of floats representing the embedding.

        Raises:
            RuntimeError: If embeddings API call fails.
        """
        url = f"{self.ollama_base_url}/api/embeddings"
        payload = {"model": "nomic-embed-text", "prompt": text}

        try:
            response = await self.client.post(url, json=payload)
            response.raise_for_status()
            data = response.json()
            embedding = data.get("embedding")
            if not embedding:
                raise RuntimeError("No embedding returned from Ollama")
            return embedding
        except Exception as e:
            logger.error(f"Failed to get embeddings: {e}")
            raise RuntimeError(f"Embeddings error: {e}") from e

    async def _compute_task_embeddings(self):
        """Compute and cache embeddings for each task type if not already done."""
        if self._task_embeddings:
            return
        logger.info("Precomputing task embeddings using nomic-embed-text...")
        for task, prompt in self._example_prompts.items():
            try:
                emb = await self._get_embeddings(prompt)
                self._task_embeddings[task] = emb
                logger.debug(f"Computed embedding for task: {task}")
            except Exception as e:
                logger.warning(f"Could not compute embedding for task {task}: {e}")
                # Fallback: empty embedding will cause similarity to be low, but we can still use keywords
                self._task_embeddings[task] = []

    def _cosine_similarity(self, a: List[float], b: List[float]) -> float:
        """Compute cosine similarity between two vectors."""
        if not a or not b or len(a) != len(b):
            return 0.0
        dot = sum(x * y for x, y in zip(a, b))
        norm_a = sum(x * x for x in a) ** 0.5
        norm_b = sum(y * y for y in b) ** 0.5
        if norm_a == 0 or norm_b == 0:
            return 0.0
        return dot / (norm_a * norm_b)

    async def _classify_with_keywords(self, prompt: str) -> Optional[str]:
        """
        Classify prompt using keyword matching.

        Returns:
            Task type if confident match, else None.
        """
        prompt_lower = prompt.lower()
        scores = {task: 0 for task in self.TASK_TYPES}
        for task, keywords in self.KEYWORD_RULES.items():
            for kw in keywords:
                if kw in prompt_lower:
                    scores[task] += 1
        # If a task has at least 2 keyword matches, return it
        max_score = max(scores.values())
        if max_score >= 2:
            best_task = max(scores, key=scores.get)
            logger.info(f"Keyword classification: {best_task} (score={max_score})")
            return best_task
        return None

    async def _classify_with_embeddings(self, prompt: str) -> str:
        """
        Classify prompt using embeddings and cosine similarity.

        Returns:
            Task type with highest similarity.
        """
        await self._compute_task_embeddings()
        try:
            prompt_emb = await self._get_embeddings(prompt)
        except Exception as e:
            logger.error(f"Failed to get embeddings for prompt: {e}. Falling back to 'general'")
            return "general"

        best_task = "general"
        best_sim = -1.0
        for task, task_emb in self._task_embeddings.items():
            if not task_emb:
                continue
            sim = self._cosine_similarity(prompt_emb, task_emb)
            if sim > best_sim:
                best_sim = sim
                best_task = task
        logger.info(f"Embedding classification: {best_task} (similarity={best_sim:.3f})")
        return best_task

    async def classify_task(self, prompt: str) -> str:
        """
        Classify the prompt into one of the task types.

        First uses keyword matching; if uncertain, uses embeddings.

        Returns:
            Task type string.
        """
        # Try keyword matching first
        keyword_task = await self._classify_with_keywords(prompt)
        if keyword_task:
            return keyword_task

        # Otherwise use embeddings
        logger.info("Keyword classification uncertain, using embeddings...")
        return await self._classify_with_embeddings(prompt)

    async def _call_model(self, model: str, prompt: str, retries: int = 1) -> str:
        """
        Call an Ollama model with the given prompt.

        Args:
            model: Model name.
            prompt: Input prompt.
            retries: Number of additional retries on failure.

        Returns:
            Model response text.

        Raises:
            Exception: If all attempts fail.
        """
        url = f"{self.ollama_base_url}/api/generate"
        payload = {
            "model": model,
            "prompt": prompt,
            "stream": False,
            "options": {"temperature": 0.7, "num_predict": 2048},
        }

        for attempt in range(retries + 1):
            try:
                response = await self.client.post(url, json=payload)
                response.raise_for_status()
                data = response.json()
                result = data.get("response", "").strip()
                if not result:
                    raise ValueError("Empty response from model")
                return result
            except Exception as e:
                logger.warning(f"Attempt {attempt+1} failed for model {model}: {e}")
                if attempt == retries:
                    raise Exception(f"Model {model} failed after {retries+1} attempts: {e}") from e
                await asyncio.sleep(1)  # brief delay before retry
        # Should never reach here
        raise Exception(f"Unexpected failure calling {model}")

    async def _route_coding(self, prompt: str, logs: List[str]) -> Tuple[str, str]:
        """Handle coding tasks using codellama:34b with fallback."""
        primary = self.MODEL_MAPPING["coding"]["primary"]
        fallback = self.MODEL_MAPPING["coding"]["fallback"]
        logs.append(f"Routing to coding task: primary model {primary} (fallback {fallback})")

        try:
            response = await self._call_model(primary, prompt)
            logs.append(f"Successfully used primary model {primary}")
            return primary, response
        except Exception as e:
            logs.append(f"Primary model {primary} failed: {e}. Falling back to {fallback}")
            try:
                response = await self._call_model(fallback, prompt)
                logs.append(f"Successfully used fallback model {fallback}")
                return fallback, response
            except Exception as e2:
                logs.append(f"Fallback model {fallback} also failed: {e2}")
                raise Exception(f"All models failed for coding task: {e2}") from e2

    async def _route_trading(self, prompt: str, logs: List[str]) -> Tuple[str, str]:
        """
        Handle trading tasks: generate signal with arcx, then validate with amara.
        Returns model="arcx" and combined response.
        """
        primary = self.MODEL_MAPPING["trading"]["primary"]
        fallback = self.MODEL_MAPPING["trading"]["fallback"]
        logs.append(f"Routing to trading task: primary model {primary} with automatic chaining to amara")

        # Step 1: generate trading signal
        try:
            signal = await self._call_model(primary, prompt)
            logs.append(f"Trading signal generated by {primary}")
        except Exception as e:
            logs.append(f"Primary model {primary} failed: {e}. Falling back to {fallback} for signal generation")
            try:
                signal = await self._call_model(fallback, prompt)
                logs.append(f"Trading signal generated by fallback {fallback}")
            except Exception as e2:
                logs.append(f"Fallback model {fallback} also failed: {e2}")
                raise Exception(f"Unable to generate trading signal: {e2}") from e2

        # Step 2: validate with amara
        validation_prompt = f"Validate the following trading signal for risk and compliance:\n{signal}"
        try:
            validation = await self._call_model("amara", validation_prompt)
            logs.append("Risk validation completed using amara")
        except Exception as e:
            logs.append(f"amara validation failed: {e}. Proceeding without validation.")
            validation = "Risk validation unavailable due to model error."

        combined_response = f"Trading Signal:\n{signal}\n\nRisk Validation:\n{validation}"
        return primary, combined_response

    async def _route_risk_analysis(self, prompt: str, logs: List[str]) -> Tuple[str, str]:
        """Handle risk analysis tasks using amara with fallback to phi4."""
        primary = self.MODEL_MAPPING["risk_analysis"]["primary"]
        fallback = self.MODEL_MAPPING["risk_analysis"]["fallback"]
        logs.append(f"Routing to risk_analysis task: primary model {primary} (fallback {fallback})")

        try:
            response = await self._call_model(primary, prompt)
            logs.append(f"Successfully used primary model {primary}")
            return primary, response
        except Exception as e:
            logs.append(f"Primary model {primary} failed: {e}. Falling back to {fallback}")
            try:
                response = await self._call_model(fallback, prompt)
                logs.append(f"Successfully used fallback model {fallback}")
                return fallback, response
            except Exception as e2:
                logs.append(f"Fallback model {fallback} also failed: {e2}")
                raise Exception(f"All models failed for risk_analysis: {e2}") from e2

    async def _route_research(self, prompt: str, logs: List[str]) -> Tuple[str, str]:
        """Handle research tasks using llama3.1:8b with fallback to phi4."""
        primary = self.MODEL_MAPPING["research"]["primary"]
        fallback = self.MODEL_MAPPING["research"]["fallback"]
        logs.append(f"Routing to research task: primary model {primary} (fallback {fallback})")

        try:
            response = await self._call_model(primary, prompt)
            logs.append(f"Successfully used primary model {primary}")
            return primary, response
        except Exception as e:
            logs.append(f"Primary model {primary} failed: {e}. Falling back to {fallback}")
            try:
                response = await self._call_model(fallback, prompt)
                logs.append(f"Successfully used fallback model {fallback}")
                return fallback, response
            except Exception as e2:
                logs.append(f"Fallback model {fallback} also failed: {e2}")
                raise Exception(f"All models failed for research: {e2}") from e2

    async def _route_vision(self, prompt: str, logs: List[str]) -> Tuple[str, str]:
        """Handle vision tasks using llava:13b (no fallback)."""
        primary = self.MODEL_MAPPING["vision"]["primary"]
        logs.append(f"Routing to vision task: primary model {primary} (no fallback)")

        try:
            response = await self._call_model(primary, prompt)
            logs.append(f"Successfully used model {primary}")
            return primary, response
        except Exception as e:
            logs.append(f"Vision model {primary} failed: {e}")
            raise Exception(f"Vision task failed: {e}") from e

    async def _route_general(self, prompt: str, logs: List[str]) -> Tuple[str, str]:
        """Handle general tasks using mistral with fallback to llama3.1:8b."""
        primary = self.MODEL_MAPPING["general"]["primary"]
        fallback = self.MODEL_MAPPING["general"]["fallback"]
        logs.append(f"Routing to general task: primary model {primary} (fallback {fallback})")

        try:
            response = await self._call_model(primary, prompt)
            logs.append(f"Successfully used primary model {primary}")
            return primary, response
        except Exception as e:
            logs.append(f"Primary model {primary} failed: {e}. Falling back to {fallback}")
            try:
                response = await self._call_model(fallback, prompt)
                logs.append(f"Successfully used fallback model {fallback}")
                return fallback, response
            except Exception as e2:
                logs.append(f"Fallback model {fallback} also failed: {e2}")
                raise Exception(f"All models failed for general task: {e2}") from e2

    async def route(self, prompt: str, task_type_override: Optional[str] = None) -> Dict:
        """
        Route a prompt to the appropriate model(s).

        Args:
            prompt: User input text.
            task_type_override: If provided, skip classification and use this task type.

        Returns:
            Dictionary with keys: model (primary model used), response (text), logs (list of strings).
        """
        logs: List[str] = []
        logs.append(f"Received prompt (first 100 chars): {prompt[:100]}...")

        # Determine task type
        if task_type_override:
            task_type = task_type_override
            logs.append(f"Task type overridden to: {task_type}")
            if task_type not in self.TASK_TYPES:
                raise ValueError(f"Invalid task_type_override: {task_type}. Allowed: {self.TASK_TYPES}")
        else:
            task_type = await self.classify_task(prompt)
            logs.append(f"Classified task type as: {task_type}")

        # Route based on task type
        try:
            if task_type == "coding":
                model_used, response = await self._route_coding(prompt, logs)
            elif task_type == "trading":
                model_used, response = await self._route_trading(prompt, logs)
            elif task_type == "risk_analysis":
                model_used, response = await self._route_risk_analysis(prompt, logs)
            elif task_type == "research":
                model_used, response = await self._route_research(prompt, logs)
            elif task_type == "vision":
                model_used, response = await self._route_vision(prompt, logs)
            else:  # general
                model_used, response = await self._route_general(prompt, logs)

            logs.append(f"Routing completed successfully. Model used: {model_used}")
            return {"model": model_used, "response": response, "logs": logs}
        except Exception as e:
            logs.append(f"Routing failed: {str(e)}")
            raise RuntimeError(f"Routing error: {e}") from e


# ------------------------------
# FastAPI application
# ------------------------------
app = FastAPI(title="ARK95X Model Router", description="Intelligent model routing for Ollama")
router_instance: Optional[ModelRouter] = None


@app.on_event("startup")
async def startup_event():
    """Initialize the ModelRouter on startup."""
    global router_instance
    ollama_url = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
    timeout = float(os.getenv("OLLAMA_TIMEOUT", "120"))
    router_instance = ModelRouter(ollama_base_url=ollama_url, timeout=timeout)
    logger.info(f"ModelRouter initialized with Ollama at {ollama_url}")


@app.on_event("shutdown")
async def shutdown_event():
    """Clean up resources."""
    if router_instance:
        await router_instance.close()
        logger.info("ModelRouter shut down")


@app.post("/api/route", response_model=RouteResponse)
async def route_request(request: RouteRequest):
    """
    Endpoint to route a prompt to the optimal model.

    - If task_type_override is provided, classification is skipped.
    - Returns the model used, the response text, and detailed logs.
    """
    if not router_instance:
        raise HTTPException(status_code=503, detail="Router not initialized")

    try:
        result = await router_instance.route(
            prompt=request.prompt,
            task_type_override=request.task_type_override,
        )
        return RouteResponse(
            model=result["model"],
            response=result["response"],
            logs=result["logs"],
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception("Unexpected error during routing")
        raise HTTPException(status_code=500, detail=f"Internal routing error: {str(e)}")


# ------------------------------
# Optional: run with uvicorn directly
# ------------------------------
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)