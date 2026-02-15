#!/bin/bash

# Quick install script for Aider (AI terminal assistant)

# Don't exit on error - we want to handle failures gracefully
set +e

echo "🤖 Installing Aider - AI Terminal Assistant"
echo "==========================================="
echo ""

# Check if pip3 is available
if ! command -v pip3 &> /dev/null; then
    echo "📦 Installing pip3..."
    if command -v dnf &> /dev/null; then
        sudo dnf install -y python3-pip
    else
        echo "❌ Please install pip3 first"
        exit 1
    fi
fi

# Install aider using aider-install (handles Python version compatibility)
echo "📥 Installing Aider..."
echo "   Note: Using aider-install for Python 3.14 compatibility..."

# First install aider-install
if pip3 install --user aider-install; then
    # Then use it to install aider (creates isolated Python 3.12 environment)
    if ! python3 -m aider_install.install 2>/dev/null; then
        if command -v aider-install &> /dev/null; then
            aider-install
        else
            echo "⚠️  aider-install didn't work. Trying alternative method..."
            echo "   Try running: bash ~/Projects/install-ai-terminal-uv.sh"
            exit 1
        fi
    fi
else
    echo "❌ Failed to install aider-install"
    echo "   Try the alternative method: bash ~/Projects/install-ai-terminal-uv.sh"
    exit 1
fi

# Ensure ~/.local/bin is in PATH
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
echo "💡 Tip: You can create an alias in ~/.zshrc:"
echo "   alias ai='aider'"
echo ""
