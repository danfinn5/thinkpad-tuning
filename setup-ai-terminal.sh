#!/bin/bash

# Setup script for AI terminal assistant (Aider)
# This script installs Aider and helps configure it with your OpenAI API key

set -e

echo "🤖 Setting up AI terminal assistant (Aider)..."
echo ""

# Check if pip is available
if ! command -v pip3 &> /dev/null; then
    echo "📦 Installing pip..."
    if command -v dnf &> /dev/null; then
        sudo dnf install -y python3-pip
    elif command -v yum &> /dev/null; then
        sudo yum install -y python3-pip
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y python3-pip
    else
        echo "❌ Could not find a package manager. Please install pip3 manually."
        exit 1
    fi
fi

# Install aider
echo "📥 Installing Aider..."
pip3 install --user aider-chat

# Get the user's local bin directory
USER_BIN="$HOME/.local/bin"
mkdir -p "$USER_BIN"

# Check if aider is in PATH
if ! command -v aider &> /dev/null; then
    echo ""
    echo "⚠️  Aider installed but not in PATH."
    echo "   Add this to your ~/.zshrc:"
    echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
    
    # Check if it's already in .zshrc
    if ! grep -q "\$HOME/.local/bin" ~/.zshrc 2>/dev/null; then
        echo "   Would you like me to add it automatically? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
            echo "✅ Added to ~/.zshrc"
        fi
    fi
fi

# Setup API key
echo ""
echo "🔑 OpenAI API Key Setup"
echo "   You'll need your OpenAI API key from: https://platform.openai.com/api-keys"
echo ""

if [ -z "$OPENAI_API_KEY" ]; then
    echo "   Enter your OpenAI API key (or press Enter to skip and set it later):"
    read -r api_key
    
    if [ -n "$api_key" ]; then
        # Add to .zshrc
        if ! grep -q "OPENAI_API_KEY" ~/.zshrc 2>/dev/null; then
            echo "" >> ~/.zshrc
            echo "# OpenAI API Key for Aider" >> ~/.zshrc
            echo "export OPENAI_API_KEY=\"$api_key\"" >> ~/.zshrc
            echo "✅ API key added to ~/.zshrc"
        else
            echo "⚠️  OPENAI_API_KEY already exists in ~/.zshrc"
            echo "   Please update it manually if needed."
        fi
        
        # Also set it for current session
        export OPENAI_API_KEY="$api_key"
    fi
else
    echo "✅ OPENAI_API_KEY is already set in your environment"
fi

echo ""
echo "✨ Setup complete!"
echo ""
echo "📖 Usage:"
echo "   aider                    # Start aider in current directory"
echo "   aider file.py            # Edit a specific file"
echo "   aider --help             # See all options"
echo ""
echo "💡 Tip: Run 'source ~/.zshrc' or open a new terminal to use aider"
