import base64
import io
import json
import os
import socket
import threading
import time
import urllib.request

import torch
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from loguru import logger
from PIL import Image
from pydantic import BaseModel
from transformers import AutoProcessor, AutoModelForVision2Seq

# ---------------------------------------------------------------------------
# Auto-discovery: announce this server's current LAN address to Supabase so
# the app never needs a hardcoded IP. If the wifi hands out a new IP, the
# next heartbeat updates it and every client picks it up automatically.
# ---------------------------------------------------------------------------
SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://zxudswchxzfmfydulrvi.supabase.co")
SUPABASE_ANON_KEY = os.environ.get(
    "SUPABASE_ANON_KEY",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp4dWRzd2NoeHpmbWZ5ZHVscnZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY1MzI5ODIsImV4cCI6MjEwMjEwODk4Mn0.i6qbTyW2fnNkdF4enIIIJzCnTVY1pRHntVIFqyOisDU",
)
PORT = int(os.environ.get("PORT", "5000"))
HEARTBEAT_SECONDS = 20


def lan_ip() -> str:
    """Local network IP of this machine (no traffic is actually sent)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def announce_forever():
    while True:
        url = f"http://{lan_ip()}:{PORT}"
        body = json.dumps({"id": "default", "url": url}).encode()
        req = urllib.request.Request(
            f"{SUPABASE_URL}/rest/v1/ai_servers",
            data=body,
            method="POST",
            headers={
                "apikey": SUPABASE_ANON_KEY,
                "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
                "Content-Type": "application/json",
                "Prefer": "resolution=merge-duplicates",
            },
        )
        try:
            urllib.request.urlopen(req, timeout=10).read()
            logger.info(f"Announced AI server at {url}")
        except Exception as e:  # noqa: BLE001 — keep the heartbeat alive
            logger.warning(f"Could not announce server address: {e}")
        time.sleep(HEARTBEAT_SECONDS)


logger.info("Initializing SmolVLM-500M-Instruct. This may take a moment to download the first time...")
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
logger.info(f"Using device: {DEVICE}")

# Initialize model and processor globally
processor = AutoProcessor.from_pretrained("HuggingFaceTB/SmolVLM-500M-Instruct")
model = AutoModelForVision2Seq.from_pretrained(
    "HuggingFaceTB/SmolVLM-500M-Instruct",
    torch_dtype=torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16,
).to(DEVICE)
logger.success("Model loaded successfully!")

app = FastAPI()

# The Flutter web build calls this server from the browser — without CORS
# headers every request would be blocked before it reaches us.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

threading.Thread(target=announce_forever, daemon=True).start()

class GenerateRequest(BaseModel):
    prompt: str
    image_b64: str = None

@app.post("/generate")
def generate(req: GenerateRequest):
    logger.info(f"Received request with prompt: {req.prompt}")
    
    messages = [
        {
            "role": "user",
            "content": []
        }
    ]
    
    image = None
    if req.image_b64:
        image_bytes = base64.b64decode(req.image_b64)
        image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        messages[0]["content"].append({"type": "image"})
        logger.info("Attached image to request.")
        
    messages[0]["content"].append({"type": "text", "text": req.prompt})

    prompt_text = processor.apply_chat_template(messages, add_generation_prompt=True)
    
    if image:
        inputs = processor(text=prompt_text, images=[image], return_tensors="pt")
    else:
        inputs = processor(text=prompt_text, return_tensors="pt")
        
    inputs = inputs.to(DEVICE)
    
    logger.info("Generating response...")
    generated_ids = model.generate(**inputs, max_new_tokens=512)
    generated_texts = processor.batch_decode(
        generated_ids,
        skip_special_tokens=True,
    )
    
    output = generated_texts[0]
    
    # Extract only the assistant's response (removing the user prompt)
    if "Assistant:" in output:
        output = output.split("Assistant:")[-1].strip()
    
    logger.success(f"Generated response: {output[:100]}...")
    return {"text": output}

@app.get("/health")
def health():
    return {"ok": True}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
