#!/bin/bash
# ============================================================
# setup.sh — Executa UNA SOLA VEGADA abans de res
# Necessita AWS CLI configurat amb les credencials del Learner Lab
# ============================================================

REGION="us-east-1"
BUCKET="tfstate-cv-challenge"

echo "🪣 Creant bucket S3 per l'estat de Terraform..."
aws s3 mb s3://$BUCKET --region $REGION

echo "🔒 Activant versionat del bucket..."
aws s3api put-bucket-versioning \
  --bucket $BUCKET \
  --versioning-configuration Status=Enabled

echo "✅ Llest! Ara pots fer push i els workflows funcionaran."
echo ""
echo "📋 Recorda afegir aquests secrets a GitHub:"
echo "   Settings → Secrets and variables → Actions → New repository secret"
echo ""
echo "   AWS_ACCESS_KEY_ID     → Learner Lab > AWS Details"
echo "   AWS_SECRET_ACCESS_KEY → Learner Lab > AWS Details"
echo "   AWS_SESSION_TOKEN     → Learner Lab > AWS Details"
echo "   AWS_REGION            → us-east-1"
