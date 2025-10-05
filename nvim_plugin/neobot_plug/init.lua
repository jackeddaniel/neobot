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

-- Clean markdown but preserve code blocks
local function clean_markdown_preserve_code(text)
	local lines = {}
	local in_code_block = false

	for line in text:gmatch("[^\r\n]+") do
		if line:match("^```") then
			in_code_block = not in_code_block
			table.insert(lines, line)
		else
			if in_code_block then
				table.insert(lines, line)
			else
				local cleaned = line
				cleaned = cleaned:gsub("%*%*", "") -- bold
				cleaned = cleaned:gsub("%*", "") -- italic/bullets
				cleaned = cleaned:gsub("_", "") -- underscores
				cleaned = cleaned:gsub("^%s*[%*%-+]%s+", "") -- list markers
				cleaned = cleaned:gsub("^#+%s*", "") -- headers
				table.insert(lines, cleaned)
			end
		end
	end

	return table.concat(lines, "\n")
end

-- Show in floating window
local function show_in_floating_window(text, title, programming_lang)
	title = title or "agent Output"
	programming_lang = programming_lang or (config.auto_detect_language and detect_language() or "text")

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(buf, "filetype", programming_lang)

	local cleaned_text = clean_markdown_preserve_code(text)
	local lines = {}
	for s in cleaned_text:gmatch("[^\r\n]+") do
		table.insert(lines, s)
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local width = math.min(math.floor(vim.o.columns * 0.7), 120)
	local height = math.min(math.floor(vim.o.lines * 0.5), #lines + 2)
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
	vim.api.nvim_win_set_option(win, "wrap", true)
	vim.api.nvim_win_set_option(win, "linebreak", true)
	vim.api.nvim_win_set_option(win, "cursorline", true)

	-- Keymaps for floating window
	local keymap_opts = { buffer = buf, silent = true, nowait = true }

	local function safe_close()
		if vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end

	vim.keymap.set("n", "q", safe_close, keymap_opts)
	vim.keymap.set("n", "<Esc>", safe_close, keymap_opts)
end

-- Spinner (simple version)
local function start_spinner(msg)
	if config.spinner_enabled then
		vim.notify(msg .. " …", vim.log.levels.INFO)
	end
end
local function stop_spinner() end

-- Make agent request (generic)
local function agent_request(endpoint, callback)
	local bufnr = vim.api.nvim_get_current_buf()
	local session_id = buffer_sessions[bufnr]

	local code = get_visual_selection()
	if code == "" then
		vim.notify("⚠️ No code selected", vim.log.levels.WARN)
		return
	end

	-- Start session if not exists
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
			vim.notify("🆕 Started agent session for buffer", vim.log.levels.INFO)
		else
			vim.notify("❌ Failed to start session", vim.log.levels.ERROR)
			return
		end
	end

	start_spinner("Processing…")
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

	callback(result, code, session_id)
end

-- Explain
function M.explain()
	agent_request("/explain", function(result)
		if result.explanation then
			show_in_floating_window(result.explanation, "Explain")
		end
	end)
end

-- Fix
function M.fix()
	agent_request("/fix", function(result)
		if result.fixed_code then
			show_in_floating_window(result.fixed_code, "Fix")
		end
	end)
end

-- Method completion in floating window
function M.complete_method()
	agent_request("/method_completion", function(result)
		if result.completed_method then
			show_in_floating_window(result.completed_method, "Method Completion")
		end
	end)
end

-- Autofill method in buffer
function M.autocomplete_method()
	agent_request("/method_completion", function(result, code, session_id)
		if result.completed_method then
			local bufnr = vim.api.nvim_get_current_buf()
			local start_pos = vim.fn.getpos("'<")
			local end_pos = vim.fn.getpos("'>")
			vim.api.nvim_buf_set_lines(
				bufnr,
				start_pos[2] - 1,
				end_pos[2],
				false,
				vim.split(result.completed_method, "\n")
			)
			vim.notify("✅ Method autocompleted", vim.log.levels.INFO)

			-- Store in session
			local session = sessions[session_id]
			session["history"] = session["history"] or {}
			table.insert(session["history"], { role = "user", content = code })
			table.insert(session["history"], { role = "assistant", content = result.completed_method })
		end
	end)
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
