#!/bin/bash

echo "=== ComfyUI パス自動検出 ==="
COMFY=""

# よくある候補を順にチェック
for candidate in \
  /app/ComfyUI \
  /workspace/ComfyUI \
  /workspace/runpod-slim/ComfyUI \
  /opt/ComfyUI \
  /root/ComfyUI \
  /home/user/ComfyUI; do
  if [ -d "$candidate" ]; then
    COMFY=$candidate
    echo "✅ ComfyUI発見: $COMFY"
    break
  fi
done

# 見つからない場合はfindで探す
if [ -z "$COMFY" ]; then
  echo "候補から見つからないのでfindで検索中..."
  COMFY=$(find / -maxdepth 6 -name "main.py" -path "*/ComfyUI/*" 2>/dev/null | head -1 | xargs dirname)
fi

if [ -z "$COMFY" ]; then
  echo "❌ ComfyUIが見つかりませんでした。終了します。"
  exit 1
fi

BASE=$COMFY/models
CUSTOM=$COMFY/custom_nodes

# スクリプトの保存先をCOMFYの親ディレクトリに
WORKDIR=$(dirname $COMFY)

echo "COMFY: $COMFY"
echo "BASE: $BASE"
echo "WORKDIR: $WORKDIR"

echo "=== extra_model_paths.yaml 設定 ==="
cat > $COMFY/extra_model_paths.yaml << EOF
comfyui:
     base_path: $COMFY/
     checkpoints: models/checkpoints/
     text_encoders: |
          models/text_encoders/
          models/clip/
     clip_vision: models/clip_vision/
     configs: models/configs/
     controlnet: models/controlnet/
     diffusion_models: |
                  models/diffusion_models
                  models/unet
     embeddings: models/embeddings/
     loras: models/loras/
     upscale_models: models/upscale_models/
     vae: models/vae/
     audio_encoders: models/audio_encoders/
     model_patches: models/model_patches/
EOF
echo "✅ extra_model_paths.yaml 完了"

echo "=== カスタムノード インストール ==="
mkdir -p $CUSTOM

# MuffinsVRFixes（VR360/180ノード）
[ ! -d "$CUSTOM/MuffinsVRFixes" ] && \
  git clone https://github.com/Ragamuffin20/MuffinsVRFixes.git $CUSTOM/MuffinsVRFixes

# KJNodes（LTX2に必須）
[ ! -d "$CUSTOM/ComfyUI-KJNodes" ] && \
  git clone https://github.com/kijai/ComfyUI-KJNodes.git $CUSTOM/ComfyUI-KJNodes

# requirements.txtがあるノードはpipも実行
for dir in $CUSTOM/*/; do
  if [ -f "$dir/requirements.txt" ]; then
    echo "pip install: $dir"
    pip install -r "$dir/requirements.txt" -q
  fi
done
echo "✅ カスタムノード完了"

echo "=== ワークフローをブラウザに登録 ==="
mkdir -p $COMFY/user/default/workflows
cp -rn $CUSTOM/MuffinsVRFixes/Workflows/. $COMFY/user/default/workflows/
echo "✅ ワークフロー登録完了"

echo "=== LTX-2 モデルダウンロード開始 ==="

mkdir -p $BASE/unet/LTX2

# マージモデル SFW版
wget -nc -P $BASE/unet/LTX2 \
  "https://huggingface.co/Phr00t/LTX2-Rapid-Merges/resolve/main/sfw/ltx2-phr00tmerge-sfw-v5.safetensors"

# マージモデル NSFW版
wget -nc -O $BASE/unet/LTX2/ltx2-phr00tmerge-nsfw-v62.safetensors \
  "https://huggingface.co/Phr00t/LTX2-Rapid-Merges/resolve/main/nsfw/ltx2-phr00tmerge-nsfw-v62.safetensors"

# dev fp8
wget -nc -P $BASE/unet/LTX2 \
  "https://huggingface.co/Kijai/LTXV2_comfy/resolve/main/diffusion_models/ltx-2-19b-dev-fp8_transformer_only.safetensors"

# text encoders
mkdir -p $BASE/text_encoders/LTX2
wget -nc -P $BASE/text_encoders/LTX2 \
  "https://huggingface.co/Kijai/LTXV2_comfy/resolve/main/text_encoders/ltx-2-19b-embeddings_connector_dev_bf16.safetensors"

# VAE
mkdir -p $BASE/vae
wget -nc -P $BASE/vae \
  "https://huggingface.co/Kijai/LTXV2_comfy/resolve/main/VAE/LTX2_video_vae_bf16.safetensors"
wget -nc -P $BASE/vae \
  "https://huggingface.co/Kijai/LTXV2_comfy/resolve/main/VAE/LTX2_audio_vae_bf16.safetensors"

echo "=== 全て完了！ ==="
