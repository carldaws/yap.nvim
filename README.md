# yap.nvim

> Can't quit vim but still need to tweet? Yap's got you covered.

Finally, you can chase that sweet monetization payout without ever leaving your beloved text editor. Post directly to X (formerly Twitter) from the comfort of your modal editing paradise.

## Features

- Post tweets using the `:Yap` command
- OAuth 1.0a authentication
- Secure credential management via environment variables
- Character count validation
- 500 posts per month (X API limit - after that you're back to the web app like a caveman)

## Requirements

- Neovim 0.7+ (obviously)
- `curl` and `openssl` (you probably have these)
- X Developer account with API credentials
- An irrepressible need to share your thoughts without leaving the terminal

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "carldaws/yap.nvim",
  opts = {},
  cmd = "Yap",
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "carldaws/yap.nvim",
  config = function()
    require("yap").setup()
  end,
}
```

## Setup

### 1. Create an X App

1. Go to [X Developer Portal](https://developer.x.com/en/portal/dashboard)
2. Create a new app (or use an existing one)
3. In your app settings, ensure you have **Read and Write** permissions (you'll have to setup the app as if you'll use Sign in with X to enable read and write permissions)
4. Get the access token and secret for your account by going to the Keys and tokens section of the app on your developer dashboard
5. Make a note of the following credentials:
   - API Key (Consumer Key)
   - API Secret (Consumer Secret)
   - Access Token
   - Access Token Secret

### 2. Configure Credentials

There are two ways to provide your X API credentials:

#### Option A: Environment Variables (Recommended)

Add these to your shell configuration (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
export X_API_KEY="your_api_key_here"
export X_API_SECRET="your_api_secret_here"
export X_ACCESS_TOKEN="your_access_token_here"
export X_ACCESS_TOKEN_SECRET="your_access_token_secret_here"
```

#### Option B: Setup Configuration

⚠️ **WARNING:** Only use this method if your Neovim configuration is private and not in public version control!

```lua
require("yap").setup({
  api_key = "your_api_key_here",
  api_secret = "your_api_secret_here",
  access_token = "your_access_token_here",
  access_token_secret = "your_access_token_secret_here",
})
```

**Security Note:**

- **NEVER** commit credentials directly in your config if your dotfiles are public
- Environment variables are the safer option for most users
- Consider using a local, untracked file to store credentials if you must use setup options

## Usage

### Post a tweet interactively

```vim
:Yap
```

Opens a prompt.

### Post a tweet directly

```vim
:Yap Just posted a tweet without leaving Neovim. I am become productivity, destroyer of context switches.
```

### Flex on your coworkers

```vim
:Yap vim > emacs
```

### Character Limit

Tweets are limited to 280 characters, just like the real thing. The plugin will show an error if you exceed this limit.

### API Limits

Remember: X's free tier gives you 500 posts per month. Use them wisely, or you'll be reduced to posting through a... _shudders_ ...web browser.

## Troubleshooting

### "Missing required credentials"

- Ensure all four credentials are provided either via environment variables or setup options
- Environment variables must be exported (use `export` in your shell config)
- Restart Neovim after setting environment variables

### "API error: Unauthorized"

- Verify your credentials are correct
- Ensure your app has Read and Write permissions
- Check that your access tokens haven't been revoked

### "Failed to parse API response"

Check your internet connection and ensure X's API is accessible from your network.

## License

MIT
