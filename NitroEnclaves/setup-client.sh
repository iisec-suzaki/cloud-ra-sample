#!/bin/bash

# Install system dependencies
echo "Installing system dependencies..."
sudo apt update
sudo apt install -y unzip

# Install Python dependencies
echo "Installing Python dependencies..."
sudo apt install -y python3-dev python3-pip python3-venv

# Create virtual environment
echo "Creating Python virtual environment..."
python3 -m venv venv

# Activate virtual environment and install packages
echo "Installing Python packages..."
source venv/bin/activate
pip install --upgrade pip
pip install cryptography cbor2 cose

echo "✅ Done"
