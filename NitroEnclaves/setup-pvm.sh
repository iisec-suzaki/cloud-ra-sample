#!/bin/bash

USERNAME="${USERNAME:-username}"

# Install dependencies
echo "Installing depedencies..."
sudo apt-get update
sudo apt-get install -y build-essential
sudo apt-get install -y docker.io
sudo apt-get install -y linux-modules-extra-aws
sudo apt-get install -y gcc make git llvm-dev libclang-dev clang

# Clone Nitro Enclaves CLI
echo "Cloning Nitro Enclaves CLI..."
git clone https://github.com/aws/aws-nitro-enclaves-cli

# Build Nitro Enclaves driver
echo "Building Nitro Enclaves driver..."
cd aws-nitro-enclaves-cli/drivers/virt/nitro_enclaves
sudo make
sudo mkdir -p /usr/lib/modules/$(uname -r)/kernel/drivers/virt/nitro_enclaves/
sudo cp nitro_enclaves.ko /usr/lib/modules/$(uname -r)/kernel/drivers/virt/nitro_enclaves/nitro_enclaves.ko
sudo insmod /usr/lib/modules/$(uname -r)/kernel/drivers/virt/nitro_enclaves/nitro_enclaves.ko

echo "Checking if Nitro Enclaves driver is loaded"
lsmod | grep nitro_enclaves
# =>
# nitro_enclaves         40960  0
cd ../../..

# Build Nitro Enclaves CLI
echo "Building Nitro Enclaves CLI..."
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USERNAME

sed "s/\$(whoami)/$USERNAME/g" ./bootstrap/nitro-cli-config > ./bootstrap/nitro-cli-config.temp
mv ./bootstrap/nitro-cli-config.temp ./bootstrap/nitro-cli-config

export NITRO_CLI_INSTALL_DIR=/

sudo make nitro-cli
sudo make vsock-proxy
sudo make NITRO_CLI_INSTALL_DIR=/ install
source /etc/profile.d/nitro-cli-env.sh
echo source /etc/profile.d/nitro-cli-env.sh >> ~/.bashrc
nitro-cli-config -i

cd ..

echo "✅ Done"
