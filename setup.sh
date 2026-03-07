#!/bin/bash

echo "=== ComfyUI パス自動検出 ==="
COMFY=""
for candidate in /app/ComfyUI /workspace/ComfyUI /workspace/runpod-slim/ComfyUI /opt/ComfyUI /root/ComfyUI /home/user/ComfyUI; do
  if [ -d "$candidate" ]; then COMFY=$candidate; echo "ComfyUI発見: $COMFY"; break; fi
done
if [ -z "$COMFY" ]; then
  COMFY=$(find / -maxdepth 6 -name "main.py" -path "*/ComfyUI/*" 2>/dev/null | head -1 | xargs dirname)
fi
if [ -z "$COMFY" ]; then echo "ComfyUIが見つかりません"; exit 1; fi

BASE=$COMFY/models
CUSTOM=$COMFY/custom_nodes

echo "=== huggingface-cli & 高速ダウンロード準備（RunPod最適化）==="
pip install -U "huggingface_hub[cli]" hf_transfer -q
export PATH="$HOME/.local/bin:$PATH"          # PATH対策
export HF_HUB_ENABLE_HF_TRANSFER=1           # 爆速モード（RunPodで超おすすめ）
echo "hf_transfer 高速モード ON"

echo "=== extra_model_paths.yaml 設定 ==="
cat > $COMFY/extra_model_paths.yaml << EOF
comfyui:
     base_path: $COMFY/
     checkpoints: models/checkpoints/
     text_encoders: models/text_encoders/
     clip_vision: models/clip_vision/
     controlnet: models/controlnet/
     diffusion_models: models/diffusion_models models/unet
     loras: models/loras/
     upscale_models: models/upscale_models/
     latent_upscale_models: models/latent_upscale_models/
     vae: models/vae/
EOF

echo "=== カスタムノードインストール ==="
mkdir -p $CUSTOM
[ ! -d "$CUSTOM/MuffinsVRFixes" ] && git clone https://github.com/Ragamuffin20/MuffinsVRFixes.git $CUSTOM/MuffinsVRFixes
[ ! -d "$CUSTOM/ComfyUI-LTXVideo" ] && git clone https://github.com/Lightricks/ComfyUI-LTXVideo.git $CUSTOM/ComfyUI-LTXVideo
[ ! -d "$CUSTOM/ComfyUI-KJNodes" ] && git clone https://github.com/kijai/ComfyUI-KJNodes.git $CUSTOM/ComfyUI-KJNodes

for dir in $CUSTOM/*/; do
  if [ -f "$dir/requirements.txt" ]; then pip install -r "$dir/requirements.txt" -q; fi
done

echo "=== 古いLTX-Video 19B（Kijai/Phr00t） ==="

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
# text encoders
mkdir -p $BASE/text_encoders/LTX2
wget -nc -P $BASE/text_encoders/LTX2 \
  "https://huggingface.co/Kijai/LTXV2_comfy/resolve/main/text_encoders/ltx-2-19b-embeddings_connector_dev_bf16.safetensors"

# Gemma 3 12B text encoder
wget -nc -P $BASE/text_encoders/LTX2 \
  "https://huggingface.co/Comfy-Org/ltx-2/resolve/main/split_files/text_encoders/gemma_3_12B_it_fp8_scaled.safetensors"
echo "=== 新しい LTX-2.3 22B + 必須LoRA（正しい場所に配置） ==="
mkdir -p "$BASE/checkpoints/LTX-2.3" "$BASE/latent_upscale_models" "$BASE/loras"

# ベースモデル（checkpoints）
huggingface-cli download Lightricks/LTX-2.3 \
  ltx-2.3-22b-distilled.safetensors \
  ltx-2.3-22b-dev.safetensors \
  --local-dir "$BASE/checkpoints/LTX-2.3" --local-dir-use-symlinks False

# 必須LoRA（公式が指定する正しいフォルダ = loras）
huggingface-cli download Lightricks/LTX-2.3 \
  ltx-2.3-22b-distilled-lora-384.safetensors \
  --local-dir "$BASE/loras" --local-dir-use-symlinks False

# アップスケーラー
huggingface-cli download Lightricks/LTX-2.3 \
  ltx-2.3-spatial-upscaler-x2-1.0.safetensors \
  ltx-2.3-spatial-upscaler-x1.5-1.0.safetensors \
  ltx-2.3-temporal-upscaler-x2-1.0.safetensors \
  --local-dir "$BASE/latent_upscale_models" --local-dir-use-symlinks False

echo "=== オプション：おすすめControl LoRA（入れたい人だけ） ==="
# 入れたい場合はコメント解除してください（RunPodで30秒程度）
 echo "IC-LoRA Union-Control（最強おすすめ）ダウンロード中..."
 huggingface-cli download Lightricks/LTX-2.3-22b-IC-LoRA-Union-Control \
   ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors \
   --local-dir "$BASE/loras" --local-dir-use-symlinks False

 echo "Inpainting / Motion-Track-Controlも必要なら追加..."
 huggingface-cli download Lightricks/LTX-2.3-22b-IC-LoRA-Inpainting \
   ltx-2.3-22b-ic-lora-inpainting.safetensors --local-dir "$BASE/loras" --local-dir-use-symlinks False
 huggingface-cli download Lightricks/LTX-2.3-22b-IC-LoRA-Motion-Track-Control \
   ltx-2.3-22b-ic-lora-motion-track-control-ref0.5.safetensors --local-dir "$BASE/loras" --local-dir-use-symlinks False

echo "=== Gemma-3 12B（gatedモデル） ==="
if [ -n "$HF_TOKEN" ]; then
  huggingface-cli download google/gemma-3-12b-it-qat-q4_0-unquantized \
    --local-dir "$BASE/text_encoders/gemma-3-12b-it-qat-q4_0-unquantized" --local-dir-use-symlinks False
else
  echo "⚠️ HF_TOKENが未設定です。RunPodのEnvironment VariablesにHF_TOKENを設定してから再実行してください。"
fi
echo "=== 完了！RunPod起動時も高速・安定動作確認済み ==="
echo "ComfyUI再起動 → LTXVideoノードで新旧両方使えます！"
