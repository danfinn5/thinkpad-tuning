#!/bin/bash

# Alternative installation using uv (modern Python package manager)
# This handles Python version isolation automatically

set -e

echo "🤖 Installing Aider with uv (Python 3.14 compatible)"
echo "==================================================="
echo ""

# Check if uv is installed
if ! command -v uv &> /dev/null; then
    echo "📦 Installing uv (modern Python package manager)..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    
    # Add uv to PATH
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi
    
    # Also add to .zshrc for future sessions
    if ! grep -q '\.cargo/env' ~/.zshrc; then
        echo '[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"' >> ~/.zshrc
    fi
fi

# Install aider using uv (automatically uses Python 3.12)
echo "📥 Installing Aider with uv..."
uv tool install --python python3.12 aider-chat@latest

# uv installs to ~/.local/bin, ensure it's in PATH
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo ""
    echo "⚠️  Adding ~/.local/bin to PATH in ~/.zshrc..."
    if ! grep -q '\$HOME/.local/bin' ~/.zshrc; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
        echo "✅ Added to ~/.zshrc"
    fi
    export PATH="$HOME/.local/bin:$PATH"
fi

# Check if API key is set
echo ""
if [ -z "$OPENAI_API_KEY" ]; then
    echo "🔑 OpenAI API Key Setup"
    echo "----------------------"
    echo ""
    echo "You need an OpenAI API key to use Aider."
    echo "Get one from: https://platform.openai.com/api-keys"
    echo ""
    read -p "Enter your OpenAI API key (or press Enter to skip): " api_key
    
    if [ -n "$api_key" ]; then
        # Add to .zshrc
        if ! grep -q "OPENAI_API_KEY" ~/.zshrc; then
            echo "" >> ~/.zshrc
            echo "# OpenAI API Key for Aider" >> ~/.zshrc
            echo "export OPENAI_API_KEY=\"$api_key\"" >> ~/.zshrc
            echo "✅ API key added to ~/.zshrc"
        fi
        export OPENAI_API_KEY="$api_key"
    else
        echo "⚠️  No API key provided. You can add it later:"
        echo "   echo 'export OPENAI_API_KEY=\"your-key-here\"' >> ~/.zshrc"
    fi
else
    echo "✅ OPENAI_API_KEY is already set"
fi

echo ""
echo "================================"
echo "✨ Installation Complete!"
echo "================================"
echo ""
echo "To use Aider:"
echo ""
echo "1. Reload your shell or open a new terminal:"
echo "   source ~/.zshrc"
echo ""
echo "2. Start Aider:"
echo "   aider                    # In current directory"
echo "   aider file.py            # Edit specific file"
echo "   aider --help             # See all options"
echo ""
