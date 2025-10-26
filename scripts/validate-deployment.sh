#!/bin/bash
set -e

echo "=========================================="
echo "Pre-Deployment Validation"
echo "=========================================="
echo ""

# 1. Check Ansible syntax
echo "[1/5] Validating Ansible playbook syntax..."
ansible-playbook --syntax-check playbooks/00-validate-environment.yml
ansible-playbook -i inventory/homologacao.ini --syntax-check playbooks/00-prepare-host-nodes.yml
ansible-playbook -i inventory/homologacao.ini --syntax-check playbooks/01-bootstrap-and-add-machines.yml
ansible-playbook --syntax-check playbooks/03-deploy-test.yml
ansible-playbook --syntax-check playbooks/00-deploy-nfs-server.yml
ansible-playbook --syntax-check playbooks/98-verify-health.yml
echo "✅ All playbooks have valid syntax"
echo ""

# 2. Check for incompatible versions
echo "[2/5] Checking for incompatible PostgreSQL versions..."
if grep -r "14/stable" juju/ 2>/dev/null; then
    echo "❌ ERROR: Found PostgreSQL 14/stable references"
    echo "   This is incompatible with Ubuntu 24.04"
    exit 1
fi
echo "✅ No incompatible PostgreSQL versions found"
echo ""

# 3. Check required files
echo "[3/5] Checking required files..."
required_files=(
    "playbooks/00-validate-environment.yml"
    "playbooks/01-bootstrap-and-add-machines.yml"
    "playbooks/03-deploy-test.yml"
    "inventory/homologacao.ini"
    "setup.sh"
)

for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ Missing required file: $file"
        exit 1
    fi
done
echo "✅ All required files present"
echo ""

# 4. Check environment variables
echo "[4/5] Checking environment configuration..."
if ! grep -q "postgresql_channel.*16/stable" inventory/homologacao.ini; then
    echo "⚠️ WARNING: homologacao.ini may not have correct PostgreSQL channel"
    echo "   Recommended: postgresql_channel: '16/stable'"
fi
echo "✅ Environment checks passed"
echo ""

# 5. Check Juju connectivity
echo "[5/5] Checking Juju connectivity..."
if command -v juju &> /dev/null; then
    if juju status &>/dev/null; then
        echo "✅ Juju is accessible"
    else
        echo "⚠️ WARNING: Juju may not be initialized"
    fi
else
    echo "⚠️ WARNING: Juju not found in PATH"
fi
echo ""

echo "=========================================="
echo "✅ Pre-Deployment Validation PASSED"
echo "=========================================="
echo ""
echo "You can now proceed with:"
echo "  ./setup.sh"
echo ""

exit 0
