local M = {}

local TWITTER_API_URL = "https://api.twitter.com/2/tweets"
local TWEET_CHAR_LIMIT = 280
local OAUTH_VERSION = "1.0"
local OAUTH_SIGNATURE_METHOD = "HMAC-SHA1"

local credentials = {}

local function percent_encode(str)
	if not str then
		return ""
	end
	str = tostring(str)
	str = str:gsub("\n", "\r\n")
	str = str:gsub("([^%w%-%.%_%~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
	return str
end

local function generate_nonce()
	return vim.fn.system("openssl rand -hex 16"):gsub("%s+", "")
end

local function get_timestamp()
	return tostring(os.time())
end

local function build_parameter_string(params)
	local keys = {}
	for k in pairs(params) do
		table.insert(keys, k)
	end
	table.sort(keys)

	local parts = {}
	for _, k in ipairs(keys) do
		table.insert(parts, percent_encode(k) .. "=" .. percent_encode(params[k]))
	end

	return table.concat(parts, "&")
end

local function generate_signature(method, url, params)
	local api_secret = credentials.api_secret
	local access_token_secret = credentials.access_token_secret

	local param_string = build_parameter_string(params)

	local signature_base = method:upper() .. "&" .. percent_encode(url) .. "&" .. percent_encode(param_string)

	local signing_key = percent_encode(api_secret) .. "&" .. percent_encode(access_token_secret)

	local cmd = string.format(
		"echo -n '%s' | openssl dgst -sha1 -hmac '%s' -binary | base64",
		signature_base:gsub("'", "'\\''"),
		signing_key:gsub("'", "'\\''")
	)

	local signature = vim.fn.system(cmd):gsub("%s+", "")
	return signature
end

local function build_auth_header(method, url, params)
	local api_key = credentials.api_key
	local access_token = credentials.access_token

	local oauth_params = {
		oauth_consumer_key = api_key,
		oauth_token = access_token,
		oauth_signature_method = OAUTH_SIGNATURE_METHOD,
		oauth_timestamp = get_timestamp(),
		oauth_nonce = generate_nonce(),
		oauth_version = OAUTH_VERSION,
	}

	local all_params = vim.tbl_extend("force", params, oauth_params)

	local signature = generate_signature(method, url, all_params)
	oauth_params.oauth_signature = signature

	local auth_parts = {}
	for k, v in pairs(oauth_params) do
		table.insert(auth_parts, string.format('%s="%s"', k, percent_encode(v)))
	end

	return "OAuth " .. table.concat(auth_parts, ", ")
end

local function tweet(text)
	if not text or text == "" then
		error("Tweet text cannot be empty")
	end

	if #text > TWEET_CHAR_LIMIT then
		error("Tweet exceeds " .. TWEET_CHAR_LIMIT .. " character limit (current: " .. #text .. ")")
	end

	local url = TWITTER_API_URL
	local method = "POST"

	local body = vim.fn.json_encode({ text = text })

	local auth_header = build_auth_header(method, url, {})

	local curl_cmd = string.format(
		"curl -s -X POST '%s' " .. "-H 'Authorization: %s' " .. "-H 'Content-Type: application/json' " .. "-d '%s'",
		url,
		auth_header:gsub("'", "'\\''"),
		body:gsub("'", "'\\''")
	)

	local response = vim.fn.system(curl_cmd)
	local ok, result = pcall(vim.fn.json_decode, response)

	if not ok then
		error("Failed to parse API response: " .. response)
	end

	if result.errors then
		local error_msg = "API error"
		if result.errors[1] then
			error_msg = error_msg .. ": " .. (result.errors[1].message or result.errors[1].title or "Unknown error")
		end
		error(error_msg)
	end

	if result.data and result.data.id then
		return {
			success = true,
			tweet_id = result.data.id,
			text = result.data.text,
		}
	else
		error("Unexpected API response format")
	end
end

function M.setup(opts)
	opts = opts or {}

	local creds = {
		api_key = opts.api_key or vim.env.X_API_KEY,
		api_secret = opts.api_secret or vim.env.X_API_SECRET,
		access_token = opts.access_token or vim.env.X_ACCESS_TOKEN,
		access_token_secret = opts.access_token_secret or vim.env.X_ACCESS_TOKEN_SECRET,
	}

	local keybind = opts.post_key or "<C-p>"

	local missing = {}
	for name, value in pairs(creds) do
		if not value or value == "" then
			table.insert(missing, name)
		end
	end

	if #missing > 0 then
		error(
			"yap.nvim: Missing required credentials: "
				.. table.concat(missing, ", ")
				.. "\n"
				.. "Set via setup opts or environment variables (X_API_KEY, X_API_SECRET, X_ACCESS_TOKEN, X_ACCESS_TOKEN_SECRET)"
		)
	end

	credentials = creds

	local function open_tweet_buffer()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
		vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
		vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
		vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

		local width = math.floor(vim.o.columns * 0.5)
		local height = math.floor(vim.o.lines * 0.25)
		local row = math.floor((vim.o.lines - height) / 2)
		local col = math.floor((vim.o.columns - width) / 2)

		local win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			width = width,
			height = height,
			row = row,
			col = col,
			style = "minimal",
			border = "rounded",
			title = string.format(" Yap (%s to post) ", keybind),
			title_pos = "center",
		})

		vim.api.nvim_set_option_value("wrap", true, { win = win })
		vim.api.nvim_set_option_value("linebreak", true, { win = win })

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
		vim.api.nvim_win_set_cursor(win, { 1, 0 })
		vim.cmd("startinsert")

		local function update_char_count()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local text = table.concat(lines, "\n")
			local count = #text
			local title = string.format(" Yap (%d/%d) - %s to post ", count, TWEET_CHAR_LIMIT, keybind)
			vim.api.nvim_win_set_config(win, { title = title })
		end

		vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
			buffer = buf,
			callback = update_char_count,
		})

		local function send_tweet()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local tweet_text = table.concat(lines, "\n"):gsub("^%s*(.-)%s*$", "%1")

			if tweet_text == "" then
				vim.notify("Tweet cannot be empty", vim.log.levels.WARN)
				return
			end

			vim.api.nvim_win_close(win, true)

			local ok, result = pcall(tweet, tweet_text)
			if ok then
				vim.notify("Tweet posted!", vim.log.levels.INFO)
			else
				vim.notify(tostring(result), vim.log.levels.ERROR)
			end
		end

		vim.api.nvim_buf_create_user_command(buf, "Send", send_tweet, {})

		if keybind and keybind ~= "" then
			vim.api.nvim_buf_set_keymap(buf, "n", keybind, ":Send<CR>", {
				noremap = true,
				silent = true,
			})
		end

		vim.api.nvim_create_autocmd("BufDelete", {
			buffer = buf,
			once = true,
			callback = function()
				if vim.api.nvim_win_is_valid(win) then
					vim.api.nvim_win_close(win, true)
				end
			end,
		})
	end

	vim.api.nvim_create_user_command("Yap", function(cmd_opts)
		local text = cmd_opts.args

		if text == "" then
			open_tweet_buffer()
		else
			local ok, result = pcall(tweet, text)
			if ok then
				vim.notify("Tweet posted!", vim.log.levels.INFO)
			else
				vim.notify(tostring(result), vim.log.levels.ERROR)
			end
		end
	end, {
		nargs = "?",
		desc = "Post a tweet to X (Twitter)",
	})
end

return M
