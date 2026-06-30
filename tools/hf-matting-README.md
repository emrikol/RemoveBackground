---
license: mit
library_name: onnx
pipeline_tag: image-segmentation
base_model: ZhengPeng7/BiRefNet-matting
tags:
- background-removal
- image-matting
- birefnet
- onnx
---

# BiRefNet-matting (ONNX)

ONNX export of [ZhengPeng7/BiRefNet-matting](https://huggingface.co/ZhengPeng7/BiRefNet-matting),
part of the MIT-licensed [BiRefNet project](https://github.com/ZhengPeng7/BiRefNet). This repo
contains **only a format conversion** (PyTorch → ONNX); all weights and credit belong to the
original authors.

## Why this export exists

BiRefNet uses `torchvision::deform_conv2d` (deformable convolution), which neither the legacy nor
the dynamo ONNX exporter supports. This export replaces that op with a mathematically equivalent
implementation built from `grid_sample` (validated numerically against `torchvision.ops.deform_conv2d`
to < 1e-3), so the model runs in ONNX Runtime / Core ML EP.

## Spec

| | |
|---|---|
| Input | `input_image`, `float32`, shape `[1, 3, 1024, 1024]`, NCHW |
| Normalization | ImageNet — mean `[0.485, 0.456, 0.406]`, std `[0.229, 0.224, 0.225]` |
| Output | `output_image`, `[1, 1, 1024, 1024]` **logits** — apply sigmoid for the alpha matte |
| Precision | fp32 (~897 MB) · opset 16 |

## License & attribution

**MIT**, following the upstream [BiRefNet project](https://github.com/ZhengPeng7/BiRefNet)
(© Peng Zheng et al.). The original PyTorch model is [`ZhengPeng7/BiRefNet-matting`](https://huggingface.co/ZhengPeng7/BiRefNet-matting).

## Citation

```bibtex
@article{BiRefNet,
  title={Bilateral Reference for High-Resolution Dichotomous Image Segmentation},
  author={Zheng, Peng and Gao, Dehong and Fan, Deng-Ping and Liu, Li and Laaksonen, Jorma and Ouyang, Wanli and Sebe, Nicu},
  journal={CAAI Artificial Intelligence Research},
  year={2024}
}
```
