# Third-Party Notices

The RemoveBackground app's own source code is licensed under the **PolyForm
Noncommercial License 1.0.0** (non-commercial, source-available — see `LICENSE`).
The app additionally **downloads at runtime** the machine-learning models and
links the libraries listed below, each under **its own license** set by its
authors. Those licenses are not changed by this project — we comply with and
attribute them here.

> ⚠️ **The app as shipped is for NON-COMMERCIAL use**, because its default model
> (RMBG-2.0) is licensed CC BY-NC 4.0. Commercial use requires either a
> commercial license from BRIA AI or removing/replacing the RMBG-2.0 model.

---

## Models

### RMBG-2.0  *(default model — bundled)*
- **License:** Creative Commons Attribution–NonCommercial 4.0 (CC BY-NC 4.0) — **non-commercial only**
- **Copyright:** © BRIA AI
- **Source:** https://huggingface.co/briaai/RMBG-2.0 — Core ML build: https://huggingface.co/VincentGOURBIN/RMBG-2-CoreML
- **Commercial use:** requires a separate agreement with BRIA AI (https://bria.ai).

### BiRefNet, BiRefNet-lite, BiRefNet-portrait  *(downloaded on demand)*
- **License:** MIT
- **Copyright:** © Peng Zheng et al. (the BiRefNet project)
- **Source:** https://github.com/ZhengPeng7/BiRefNet — ONNX builds: https://huggingface.co/onnx-community

### BiRefNet-matting (ONNX)  *(downloaded on demand)*
- **License:** MIT (following the upstream BiRefNet project)
- **Copyright:** © Peng Zheng et al.
- **Source:** ONNX export hosted at https://huggingface.co/emrikol/birefnet-matting-onnx — a format conversion (PyTorch → ONNX) of https://huggingface.co/ZhengPeng7/BiRefNet-matting

## Libraries

### ONNX Runtime  *(statically linked into the app)*
- **License:** MIT
- **Copyright:** © Microsoft Corporation
- **Source:** https://github.com/microsoft/onnxruntime — Swift package: https://github.com/microsoft/onnxruntime-swift-package-manager

---

Apple system frameworks (SwiftUI, AppKit, Core ML, Core Graphics, etc.) are used
under the macOS SDK license and require no separate attribution.

### Citation for the BiRefNet models

```bibtex
@article{BiRefNet,
  title={Bilateral Reference for High-Resolution Dichotomous Image Segmentation},
  author={Zheng, Peng and Gao, Dehong and Fan, Deng-Ping and Liu, Li and Laaksonen, Jorma and Ouyang, Wanli and Sebe, Nicu},
  journal={CAAI Artificial Intelligence Research},
  year={2024}
}
```
