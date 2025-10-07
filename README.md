# 🧠 Neobot — AI-Powered Neovim Coding Assistant

Neobot MCP is a lightweight Model Context Protocol (MCP) server paired with a Neovim plugin that brings AI coding features directly into your editor — no browser tabs, no context switching.
It uses Google Gemini to provide code explanations, bug fixes, and method completions within the context of the entire file you're working on.

## ✨ Features

**📝 Explain Code** — Select any snippet and get a contextual explanation inline.

**🛠 Bug Fixing** — Select a block, get back a fixed version of it.

**🧠 Method Completion** — Give a method prototype and let the model implement it using the file context.

**⚡ Autofill** — Directly insert the completed method below the selection.

**🪄 Session-Aware** — Each file has its own server session with conversation history.

**🪟 Beautiful Floating Windows** — Clean vertical scrolling, markdown rendering, and neat formatting.

🛑 No external dependencies on paid APIs if you have your Gemini key — everything runs locally.

## 🧰 Tech Stack

**Backend**: FastAPI + Python

**Frontend**: Neovim (Lua plugin)

**Model**: Gemini 2.5 Flash

**Communication**: REST API

## 🚀 Quick Start
1. Clone the Repo
git clone https://github.com/yourusername/neobot-mcp.git
cd neobot-mcp

2. Set up Environment

Create a .env file in the project root:
GEMINI_API_KEY=your_api_key_here

You can get your key from Google AI Studio
.

Then install backend dependencies:

cd neobot
python3 -m venv .neo
source .neo/bin/activate
pip install -r requirements.txt

3. Run the MCP Server
python server_context.py


The server will run at:
👉 http://127.0.0.1:8000

4. Install the Neovim Plugin

Put the nvim_plugin/neobot_plug directory in your Neovim runtime path (e.g. ~/.config/nvim/lua/), or use a plugin manager like lazy.nvim
:

{
  dir = "~/projects/neobot/nvim_plugin/neobot_plug",
  config = function()
    require("neobot_plug").setup()
  end
}

5. Keymaps
Mode	Keybinding	Action
Visual	<leader>me	Explain selection
Visual	<leader>mf	Fix code snippet
Visual	<leader>mc	Complete selected method
Visual	<leader>mca	Auto-insert completed method

💡 Make sure you’re in visual mode to select the snippet first.

🔁 Typical Workflow

Start editing a file in Neovim.

Visually select a block of code.

Press one of the keymaps:

<leader>me → Explain the selected snippet.

<leader>mf → Fix bugs in the snippet.

<leader>mc → Complete a method body and preview.

<leader>mca → Auto-insert the method implementation.

A floating window opens with the AI’s response (markdown formatted).

Sessions are stored per buffer, so subsequent calls retain context.

Close the floating window with q or <Esc>.

## 🧠 Session Model

Each file buffer opens a session with the backend the first time you make a request.
The full file is sent initially, and the backend maintains a history of interactions.
Subsequent snippet queries include:
- The full file content
- Your question/snippet
- Conversation history

This makes the model’s responses much more accurate and contextual, especially for multi-function files.

🧩 Extending Neobot

Because the backend is a FastAPI server, you can easily add:
- ✅ Test case generation
- 🧪 Refactoring suggestions
- 📝 Documentation generation
- 💡 Code review mode

Each feature can be exposed as a new endpoint + mapped to a keybinding in init.lua.

## 🛠 Troubleshooting

❌ Timeout on /fix → The Gemini API may take longer for large code blocks; try selecting smaller snippets.

⚠️ Deprecation Warnings → This project uses modern vim.bo and vim.wo APIs to avoid these. Make sure Neovim ≥ 0.10.

🧱 Server not found → Ensure server_context.py is running before using keymaps.
