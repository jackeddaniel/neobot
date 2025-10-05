import os
import uuid
import logging
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware
import requests
from dotenv import load_dotenv

# --- Load environment variables ---
load_dotenv()
GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
API_KEY = os.getenv("GEMINI_API_KEY")
if not API_KEY:
    raise ValueError("GEMINI_API_KEY environment variable not set!")

# --- Logging setup ---
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

# --- FastAPI setup ---
app = FastAPI(title="Full-File MCP Server")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- In-memory session storage ---
sessions = {}

# --- Pydantic models ---
class StartSessionRequest(BaseModel):
    file_name: str
    full_file: str

class SnippetRequest(BaseModel):
    session_id: str
    snippet: str
    question: str | None = None
    programming_lang: str | None = None

# --- Helper function for Gemini ---
def ai_response(prompt_text: str, timeout: int = 40):
    logging.info(f"Sending prompt to Gemini:\n{prompt_text[:500]}...")  # log first 500 chars
    payload = {"contents": [{"parts": [{"text": prompt_text}]}]}
    headers = {
        "x-goog-api-key": API_KEY,
        "Content-Type": "application/json"
    }

    try:
        response = requests.post(GEMINI_API_URL, json=payload, headers=headers, timeout=timeout)
        response.raise_for_status()
        data = response.json()
        return data["candidates"][0]["content"]["parts"][0]["text"]
    except Exception as e:
        logging.error(f"Error calling Gemini API: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

# --- Endpoints ---

@app.post("/start_session")
def start_session(req: StartSessionRequest):
    session_id = str(uuid.uuid4())
    sessions[session_id] = {
        "file_name": req.file_name,
        "full_file": req.full_file,
        "history": []
    }
    logging.info(f"Started session {session_id} for file {req.file_name}")
    return {"session_id": session_id}

@app.post("/explain")
def explain(req: SnippetRequest):
    if req.session_id not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    session = sessions[req.session_id]

    # Build prompt with limit instruction
    prompt = f"Explain the following code snippet in context of the full file in concisely:\n{req.snippet}\n"
    if req.question:
        prompt += f"Question: {req.question}\n"
    if req.programming_lang:
        prompt = f"Programming language: {req.programming_lang}\n" + prompt
    prompt += f"\nFull file:\n{session['full_file']}\n\n"

    # Include previous assistant messages
    for h in session["history"]:
        prompt += f"{h['role']}:\n{h['content']}\n"

    explanation = ai_response(prompt)

    # Store in session
    session["history"].append({"role": "user", "content": req.snippet})
    session["history"].append({"role": "assistant", "content": explanation})

    logging.info(f"Returned explanation for session {req.session_id}")
    return {"explanation": explanation}

@app.post("/fix")
def fix(req: SnippetRequest):
    if req.session_id not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")
    session = sessions[req.session_id]
    
    # Build prompt with only the snippet
    prompt = f"Fix any bugs in the following code snippet:\n\n```\n{req.snippet}\n```\n\n"
    
    if req.programming_lang:
        prompt = f"Programming language: {req.programming_lang}\n\n" + prompt
    
    prompt += "Return only the corrected code snippet."
    
    try:
        fixed_code = ai_response(prompt, timeout=60)  # timeout 60s
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error: {str(e)}")
    
    session["history"].append({"role": "user", "content": req.snippet})
    session["history"].append({"role": "assistant", "content": fixed_code})
    
    return {"fixed_code": fixed_code}
@app.post("/get_full_explanation")
def get_full_explanation(session_id: str):
    if session_id not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")
    session = sessions[session_id]
    full_exp = "\n\n".join([h["content"] for h in session["history"] if h["role"]=="assistant"])
    return {"full_explanation": full_exp}

@app.post("/method_completion")
def method_completion(req: SnippetRequest):
    if req.session_id not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    session = sessions[req.session_id]
    full_file = session["full_file"]

    # Build prompt for method completion
    prompt = f"Complete the following method within the context of the code:\n{req.snippet}\n\nFull context:\n{full_file}\n"
    if req.programming_lang:
        prompt = f"Programming language: {req.programming_lang}\n" + prompt
    prompt += "\nReturn only the completed method implementation."

    try:
        completed_method = ai_response(prompt, timeout=60)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error: {str(e)}")

    # Store in session
    session["history"].append({"role": "user", "content": req.snippet})
    session["history"].append({"role": "assistant", "content": completed_method})

    return {"completed_method": completed_method}


# --- Run locally ---
if __name__ == "__main__":
    import uvicorn
    logging.info("Starting MCP server on http://127.0.0.1:8000")
    uvicorn.run(app, host="127.0.0.1", port=8000)

