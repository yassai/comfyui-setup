#!/bin/bash
set -e

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

echo "=== huggingface-cli & 高速ダウンロード準備 ==="
pip install -U huggingface_hub hf_transfer -q
export PATH="$HOME/.local/bin:$PATH"
export HF_HUB_ENABLE_HF_TRANSFER=1
echo "hf_transfer 爆速モード ON"

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

echo "=== Custom Nodes インストール（既存ならスキップ）==="
cd $COMFY

# 必須
for repo in \
  "ltdrdata/ComfyUI-Manager" \
  "Lightricks/ComfyUI-LTXVideo" \
  "1038lab/ComfyUI-QwenVL" ; do
  name=$(basename $repo)
  if [ ! -d "$CUSTOM/$name" ]; then
    echo "インストール: $name"
    git clone --depth 1 https://github.com/$repo "$CUSTOM/$name"
    cd "$CUSTOM/$name" && pip install -r requirements.txt -q || echo "requirementsなし"
    cd $COMFY
  else
    echo "既に存在: $name → スキップ"
  fi
done

# オプション（Qwen-Image-Edit強化 + ACE拡張 + Z-Image）
for repo in \
  "lrzjason/Comfyui-QwenEditUtils" \
  "ryanontheinside/ComfyUI_RyanOnTheInside" \
  "martin-rizzo/ComfyUI-ZImagePowerNodes" ; do
  name=$(basename $repo)
  if [ ! -d "$CUSTOM/$name" ]; then
    echo "オプションインストール: $name"
    git clone --depth 1 https://github.com/$repo "$CUSTOM/$name"
    cd "$CUSTOM/$name" && pip install -r requirements.txt -q || true
    cd $COMFY
  fi
done

echo "=== モデルダウンロード（存在したら完全スキップ）==="

# 1. LTX-2.3（動画生成の主力・Distilled推奨）
if [ ! -f "$BASE/checkpoints/ltx-2.3-22b-distilled.safetensors" ]; then
  echo "LTX-2.3 Distilled ダウンロード中..."
  hf download Lightricks/LTX-2.3 --include "ltx-2.3-22b-distilled.safetensors" --local-dir "$BASE/checkpoints"
else
  echo "LTX-2.3 既に存在 → スキップ"
fi

# 2. Qwen-Image-Edit（編集特化・FP8高速版）
if [ ! -f "$BASE/diffusion_models/qwen_image_edit_fp8_e4m3fn.safetensors" ]; then
  echo "Qwen-Image-Edit ダウンロード中..."
  hf download Comfy-Org/Qwen-Image-Edit_ComfyUI --include "split_files/diffusion_models/qwen_image_edit_fp8_e4m3fn.safetensors" --local-dir "$BASE"
else
  echo "Qwen-Image-Edit 既に存在 → スキップ"
fi

# 3. ACE Step 1.5（音楽生成・Turbo AIO）
if [ ! -f "$BASE/checkpoints/ace_step_1.5_turbo_aio.safetensors" ]; then
  echo "ACE Step 1.5 Turbo ダウンロード中..."
  hf download Comfy-Org/ace_step_1.5_ComfyUI_files --include "checkpoints/ace_step_1.5_turbo_aio.safetensors" --local-dir "$BASE"
else
  echo "ACE Step 1.5 既に存在 → スキップ"
fi

# 4. Flux（ストーリーボード画像生成・最強推奨）
if [ ! -f "$BASE/unet/flux1-schnell.safetensors" ]; then
  echo "Flux.1-schnell ダウンロード中（ストーリーボード用）..."
  hf download black-forest-labs/FLUX.1-schnell --include "flux1-schnell.safetensors" --local-dir "$BASE/unet"
else
  echo "Flux 既に存在 → スキップ"
fi

# 5. Z-Image Turbo（軽量代替希望の場合のみ手動実行推奨）
# hf download Tongyi-MAI/Z-Image --include "z_image_turbo_bf16.safetensors" --local-dir "$BASE/diffusion_models"

echo "=== セットアップ完了！ ==="
echo "ComfyUIを再起動してください（RunPodならContainer Restart）"
echo "次に Manager → Update All → Restart で全ノード有効化"
echo ""
echo "ワークフロー構築のヒント："
echo "1. Qwen 3.5ノードで「アイデア＋ストーリーボード台本」生成"
echo "2. Flux → Qwen-Image-Editで各パネル画像作成"
echo "3. LTX-2.3（First Last Frame）で動画化"
echo "4. ACE Step 1.5でBGM/ボーカル自動挿入"
echo "公式サンプルワークフロー：https://docs.comfy.org/tutorials （LTX / Qwen / ACEセクション参照）"

echo "これで「テキスト入力1つ→完成動画」完全自動パイプラインが完成です！"
