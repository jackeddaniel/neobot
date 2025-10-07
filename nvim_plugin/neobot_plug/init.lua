local M = {}

-- Configuration
local config = {
	base_url = "http://localhost:8000",
	timeout = 30000, -- 30 seconds
	spinner_enabled = true,
	auto_detect_language = true,
}

-- Store session IDs per buffer
local buffer_sessions = {}

-- Detect programming language from buffer
local function detect_language()
	local ft = vim.bo.filetype
	return ft ~= "" and ft or "text"
end

-- Get visual selection
local function get_visual_selection()
	local mode = vim.fn.mode()
	if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
		vim.cmd("normal! gv")
	end

	local pos_start = vim.fn.getpos("'<")
	local pos_end = vim.fn.getpos("'>")
	local ls, cs = pos_start[2], pos_start[3]
	local le, ce = pos_end[2], pos_end[3]

	if ls == 0 or le == 0 then
		return ""
	end

	local lines = vim.fn.getline(ls, le)
	if #lines == 0 then
		return ""
	end

	if #lines == 1 then
		return string.sub(lines[1], cs, ce)
	end

	lines[#lines] = string.sub(lines[#lines], 1, ce)
	lines[1] = string.sub(lines[1], cs)

	return table.concat(lines, "\n")
end

-- Show in floating window with larger size and vertical scrolling
local function show_in_floating_window(text, title, programming_lang)
	title = title or "MCP Output"
	programming_lang = programming_lang or (config.auto_detect_language and detect_language() or "text")

	local buf = vim.api.nvim_create_buf(false, true)

	-- Use vim.bo for buffer options (set modifiable later)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = programming_lang
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].swapfile = false

	local lines = {}
	for s in text:gmatch("[^\r\n]+") do
		table.insert(lines, s:match("^%s*(.-)%s*$"))
	end

	if #lines == 0 then
		lines = { "(no output)" }
	end

	-- Set lines BEFORE making buffer non-modifiable
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	-- Window size - 70% width and 65% height
	local width = math.min(math.floor(vim.o.columns * 0.7), 120)
	local height = math.min(math.floor(vim.o.lines * 0.65), 35)

	local opts = {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
		title = " " .. title .. " ",
		title_pos = "center",
	}

	local win = vim.api.nvim_open_win(buf, true, opts)

	-- Use vim.wo for window options (modern API)
	vim.wo[win].wrap = true
	vim.wo[win].linebreak = true
	vim.wo[win].breakindent = true
	vim.wo[win].cursorline = true
	vim.wo[win].scrolloff = 3
	vim.wo[win].sidescrolloff = 5

	-- Close keymaps with safe checks
	local keymap_opts = { buffer = buf, silent = true, nowait = true }
	local function safe_close()
		if vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end

	vim.keymap.set("n", "q", safe_close, keymap_opts)
	vim.keymap.set("n", "<Esc>", safe_close, keymap_opts)

	-- Additional navigation keymaps for easier scrolling
	vim.keymap.set("n", "j", "gj", keymap_opts)
	vim.keymap.set("n", "k", "gk", keymap_opts)
	vim.keymap.set("n", "<C-d>", "<C-d>zz", keymap_opts)
	vim.keymap.set("n", "<C-u>", "<C-u>zz", keymap_opts)
end

-- Spinner (simple version)
local function start_spinner(msg)
	vim.notify(msg .. " …", vim.log.levels.INFO)
end
local function stop_spinner() end

-- Make MCP request
local function mcp_request(endpoint, opts)
	opts = opts or {}
	local bufnr = vim.api.nvim_get_current_buf()
	local session_id = buffer_sessions[bufnr]

	local code = get_visual_selection()
	if code == "" then
		vim.notify("⚠️ No code selected", vim.log.levels.WARN)
		return
	end

	-- If session doesn't exist, create one with full buffer
	if not session_id then
		local full_file = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
		local resp = vim.fn.systemlist(
			string.format(
				'curl -s -X POST %s/start_session -H "Content-Type: application/json" -d %q',
				config.base_url,
				vim.fn.json_encode({ file_name = vim.fn.bufname(bufnr), full_file = full_file })
			)
		)
		local ok, json = pcall(vim.fn.json_decode, table.concat(resp, "\n"))
		if ok and json and json.session_id then
			session_id = json.session_id
			buffer_sessions[bufnr] = session_id
			vim.notify("🆕 Started MCP session for buffer", vim.log.levels.INFO)
		else
			vim.notify("❌ Failed to start session", vim.log.levels.ERROR)
			return
		end
	end

	start_spinner("Processing")

	-- Prepare request to /explain or /fix
	local payload =
		vim.fn.json_encode({ session_id = session_id, snippet = code, programming_lang = detect_language() })
	local url = config.base_url .. endpoint
	local resp =
		vim.fn.systemlist(string.format('curl -s -X POST %s -H "Content-Type: application/json" -d %q', url, payload))

	stop_spinner()

	local ok, result = pcall(vim.fn.json_decode, table.concat(resp, "\n"))
	if not ok or not result then
		vim.notify("❌ Failed to parse server response", vim.log.levels.ERROR)
		return
	end

	-- Clean up code fences from responses (remove ``` markers)
	local function clean_code_fences(text)
		if not text then
			return text
		end
		-- Remove opening fence with optional language
		text = text:gsub("^```%w*\n", "")
		-- Remove closing fence
		text = text:gsub("\n```$", "")
		return text
	end

	if endpoint == "/explain" and result.explanation then
		show_in_floating_window(result.explanation, "Explain")
	elseif endpoint == "/fix" and result.fixed_code then
		local cleaned = clean_code_fences(result.fixed_code)
		show_in_floating_window(cleaned, "Fix")
	elseif endpoint == "/method_completion" and result.completed_method then
		local cleaned = clean_code_fences(result.completed_method)
		if opts.autofill then
			-- Autofill mode: insert completion below the selection
			local end_pos = vim.fn.getpos("'>")
			local insert_line = end_pos[2]
			vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, vim.split(cleaned, "\n"))
			vim.notify("✅ Method autocompleted", vim.log.levels.INFO)
		else
			-- Preview mode: show in floating window
			show_in_floating_window(cleaned, "Method Completion")
		end
	else
		vim.notify("⚠️ Unexpected server response", vim.log.levels.WARN)
	end
end

-- Public API
function M.explain()
	mcp_request("/explain")
end

function M.fix()
	mcp_request("/fix")
end

function M.complete_method()
	mcp_request("/method_completion", { autofill = false })
end

function M.autocomplete_method()
	mcp_request("/method_completion", { autofill = true })
end

-- Setup keymaps
function M.setup()
	local opts = { silent = true, noremap = true }
	vim.keymap.set("v", "<leader>me", M.explain, opts)
	vim.keymap.set("v", "<leader>mf", M.fix, opts)
	vim.keymap.set("v", "<leader>mc", M.complete_method, opts)
	vim.keymap.set("v", "<leader>mca", M.autocomplete_method, opts)
end

return M
