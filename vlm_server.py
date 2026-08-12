import torch
from transformers import AutoProcessor, AutoModelForVision2Seq
from PIL import Image
import base64
import io
import uvicorn
from fastapi import FastAPI
from pydantic import BaseModel
from loguru import logger

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

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=5000)
