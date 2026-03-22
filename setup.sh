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
pip install -U huggingface_hub hf_transfer -q
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


echo "=== 古いLTX-Video 19B（Kijai/Phr00t） ==="
COMFY="${COMFY:-$HOME/ComfyUI}"

echo "=== ComfyUI path: $COMFY ==="

# ディレクトリ作成
mkdir -p "$COMFY/models/unet"
mkdir -p "$COMFY/models/loras"
mkdir -p "$COMFY/models/text_encoders"
mkdir -p "$COMFY/models/vae"
mkdir -p "$COMFY/models/upscale_models"
mkdir -p "$COMFY/models/depthanything"
mkdir -p "$COMFY/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife"

# ===== ダウンロード関数 =====
hf_dl() {
  local repo="$1"
  local file="$2"
  local dest="$3"
  local target="$dest/$(basename "$file")"
  if [ -f "$target" ]; then
    echo "[SKIP] $(basename "$file") already exists"
    return
  fi
  echo "[DL] $repo / $file → $dest"
  hf download "$repo" "$file" \
    --local-dir "$dest"
}

# ===== カスタムノード git clone =====
clone_node() {
  local repo_url="$1"
  local dir_name="$2"
  local dest="$COMFY/custom_nodes/$dir_name"
  if [ -d "$dest" ]; then
    echo "[SKIP] custom_node $dir_name already exists"
    return
  fi
  echo "[CLONE] $repo_url"
  git clone "$repo_url" "$dest"
}

echo ""
echo "=== [1/5] カスタムノード ==="
clone_node "https://github.com/Ragamuffin20/MuffinsVRFixes"         "MuffinsVRFixes"
clone_node "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite" "ComfyUI-VideoHelperSuite"
clone_node "https://github.com/kijai/ComfyUI-DepthAnythingV2"        "ComfyUI-DepthAnythingV2"
clone_node "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation" "ComfyUI-Frame-Interpolation"
clone_node "https://github.com/yushan777/ComfyUI-Y7-SBS"             "ComfyUI-Y7-SBS"
clone_node "https://github.com/city96/ComfyUI-GGUF"                  "ComfyUI-GGUF"
clone_node "https://github.com/rgthree/rgthree-comfy"                "rgthree-comfy"
clone_node "https://github.com/ltdrdata/ComfyUI-Impact-Pack"         "ComfyUI-Impact-Pack"
clone_node "https://github.com/kijai/ComfyUI-KJNodes"                "ComfyUI-KJNodes"
clone_node "https://github.com/kijai/ComfyUI-LTXVideo"               "ComfyUI-LTXVideo"
clone_node "https://github.com/cubiq/ComfyUI_essentials"             "ComfyUI_essentials"

echo "=== カスタムノードの依存関係をインストール ==="
for dir in $CUSTOM/*/; do
  if [ -f "$dir/requirements.txt" ]; then
    echo "Installing requirements for $(basename "$dir")..."
    pip install -r "$dir/requirements.txt" -q
  fi
done

echo ""
echo "=== [2/5] Wan 2.1 VACE モデル (UNet / LoRA / Text Encoder / VAE) ==="
hf_dl "QuantStack/Wan2.1_14B_VACE-GGUF" \
  "Wan2.1_14B_VACE-Q8_0.gguf" \
  "$COMFY/models/unet"

hf_dl "Kijai/WanVideo_comfy" \
  "Wan21_CausVid_14B_T2V_lora_rank32.safetensors" \
  "$COMFY/models/loras"

hf_dl "Comfy-Org/Wan_2.1_ComfyUI_repackaged" \
  "split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
  "$COMFY/models/text_encoders"

hf_dl "Comfy-Org/Wan_2.1_ComfyUI_repackaged" \
  "split_files/vae/wan_2.1_vae.safetensors" \
  "$COMFY/models/vae"

echo ""
echo "=== [3/5] LTX-2 モデル (UNet / Text Encoder / VAE / LoRA) ==="
hf_dl "Kijai/LTXV2_comfy" \
  "diffusion_models/ltx-2-19b-dev-Q5_K_S.gguf" \
  "$COMFY/models/unet"

hf_dl "bartowski/gemma-3-12b-it-GGUF" \
  "gemma-3-12b-it-IQ4_XS.gguf" \
  "$COMFY/models/text_encoders"

hf_dl "Kijai/LTXV2_comfy" \
  "text_encoders/ltx-2-19b-embeddings_connector_dev_bf16.safetensors" \
  "$COMFY/models/text_encoders"

hf_dl "Kijai/LTXV2_comfy" \
  "VAE/LTX2_video_vae_bf16.safetensors" \
  "$COMFY/models/vae"

hf_dl "Kijai/LTXV2_comfy" \
  "loras/ltx-2-19b-ic-lora-detailer.safetensors" \
  "$COMFY/models/loras"

hf_dl "Kijai/LTXV2_comfy" \
  "loras/ltx-2-19b-distilled-lora-384.safetensors" \
  "$COMFY/models/loras"

echo ""
echo "=== [4/5] アップスケーラー / フレーム補間 / 深度推定 ==="
hf_dl "skbhadra/ClearRealityV1" \
  "4x-ClearRealityV1.pth" \
  "$COMFY/models/upscale_models"

hf_dl "Isi99999/Frame_Interpolation_Models" \
  "rife49.pth" \
  "$COMFY/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife"

hf_dl "Kijai/DepthAnythingV2-safetensors" \
  "depth_anything_v2_vitl_fp16.safetensors" \
  "$COMFY/models/depthanything"



# ベースモデル（checkpoints）
hf download Lightricks/LTX-2.3 \
  ltx-2.3-22b-distilled.safetensors \
  ltx-2.3-22b-dev.safetensors \
  --local-dir "$BASE/checkpoints/LTX-2.3"

# 必須LoRA（公式が指定する正しいフォルダ = loras）
hf download Lightricks/LTX-2.3 \
  ltx-2.3-22b-distilled-lora-384.safetensors \
  --local-dir "$BASE/loras"

hf download Lightricks/LTX-2.3 \
  ltx-2.3-22b-distilled-lora-dynamic_fro09_avg_rank_105_bf16.safetensors \
  --local-dir "$BASE/loras"

# アップスケーラー
hf download Lightricks/LTX-2.3 \
  ltx-2.3-spatial-upscaler-x2-1.0.safetensors \
  ltx-2.3-spatial-upscaler-x1.5-1.0.safetensors \
  ltx-2.3-temporal-upscaler-x2-1.0.safetensors \
  --local-dir "$BASE/latent_upscale_models"

hf download Kim2091/ClearRealityV1 \
  4x-ClearRealityV1_Soft.pth \
  --local-dir "$BASE/latent_upscale_models"

echo "=== オプション：おすすめControl LoRA（入れたい人だけ） ==="
# 入れたい場合はコメント解除してください（RunPodで30秒程度）
 echo "IC-LoRA Union-Control（最強おすすめ）ダウンロード中..."
 hf download Lightricks/LTX-2.3-22b-IC-LoRA-Union-Control \
   ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors \
   --local-dir "$BASE/loras"

 echo "Inpainting / Motion-Track-Controlも必要なら追加..."
 hf download Lightricks/LTX-2.3-22b-IC-LoRA-Inpainting \
   ltx-2.3-22b-ic-lora-inpainting.safetensors --local-dir "$BASE/loras"
 hf download Lightricks/LTX-2.3-22b-IC-LoRA-Motion-Track-Control \
   ltx-2.3-22b-ic-lora-motion-track-control-ref0.5.safetensors --local-dir "$BASE/loras"

echo "=== Gemma-3 12B（gatedモデル） ==="
if [ -n "$HF_TOKEN" ]; then
  hf download google/gemma-3-12b-it-qat-q4_0-unquantized \
    --local-dir "$BASE/text_encoders/gemma-3-12b-it-qat-q4_0-unquantized"
else
  echo "⚠️ HF_TOKENが未設定です。RunPodのEnvironment VariablesにHF_TOKENを設定してから再実行してください。"
fi
echo "=== 完了！RunPod起動時も高速・安定動作確認済み ==="
echo "ComfyUI再起動 → LTXVideoノードで新旧両方使えます！"
