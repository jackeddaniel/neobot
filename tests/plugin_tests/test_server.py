import os
import uuid
import logging

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="Nvim plugin test")

app.add_middleware(
    CORSMiddleware, 
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


sessions = {}

class StartSessionRequest(BaseModel):
    file_name: str
    full_file: str

class SnippetRequest(BaseModel):
    session_id: str
    snippet: str |  None = None
    question: str | None = None
    programming_lang: str | None = None




@app.post("/start_session")
def start_session(req: StartSessionRequest):
    print(f"recieved Start_session request: file -> {req.file_name} and file -> {req.full_file} \n")
    session_id = str(uuid.uuid4())
    sessions[session_id] = {
        "file_name": req.file_name,
        "full_file": req.full_file,
        "history": []
    }
    logging.info(f"Started session {session_id} for file {req.file_name}")
    print(f"returned the session_id {session_id}\n")
    return {"session_id": session_id}

@app.post("/explain")
def explain(req: SnippetRequest):
    if req.session_id not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    session = sessions[req.session_id]
    
    #testing the rendering and formatting of the nvim window with dummy responses
    explanation = req.snippet

    session["history"].append({"role": "user", "content": req.snippet})
    session["history"].append({"role": "assistant", "content": explanation})

    logging.info(f"Returned explanation for session {req.session_id}")
    return {"explanation": explanation}

# Summarizing the entire file 
@app.post("/summary")
def summary(req: SnippetRequest):
    if req.session_id not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    curr_session = sessions[req.session_id]
    
    #dummy response
    explanation = curr_session['full_file']
    
    logging.info(f"Returned explanation for session {req.session_id}")
    return {"explanation": explanation}


@app.post("/fix")
def fix(req: SnippetRequest):
    if req.session_id not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")
    session = sessions[req.session_id]

    #dummy response
    fixed_code = req.snippet
    
    session["history"].append({"role": "user", "content": req.snippet})
    session["history"].append({"role": "assistant", "content": fixed_code})
    
    return {"fixed_code": fixed_code}

@app.post("/method_completion")
def method_completion(req: SnippetRequest):
    if req.session_id not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    session = sessions[req.session_id]
    full_file = session["full_file"]

    completed_method = req.snippet

    # Store in session
    session["history"].append({"role": "user", "content": req.snippet})
    session["history"].append({"role": "assistant", "content": completed_method})

    return {"completed_method": completed_method}


# --- Run locally ---
if __name__ == "__main__":
    import uvicorn
    logging.info("Starting MCP server on http://127.0.0.1:8000")
    uvicorn.run(app, host="127.0.0.1", port=8000)

