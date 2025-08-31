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

	vim.api.nvim_create_user_command("Yap", function(cmd_opts)
		local text = cmd_opts.args

		if text == "" then
			vim.ui.input({ prompt = "Yap: " }, function(input)
				if not input or input == "" then
					return
				end

				local ok, result = pcall(tweet, input)
				if ok then
					vim.notify("Tweet posted!", vim.log.levels.INFO)
				else
					vim.notify(tostring(result), vim.log.levels.ERROR)
				end
			end)
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
