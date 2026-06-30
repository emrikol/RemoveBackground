# SPDX-FileCopyrightText: 2026 emrikol
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Export BiRefNet-matting to ONNX.

BiRefNet's ASPP uses torchvision deformable conv, which neither ONNX exporter
supports. We replace `torchvision.ops.deform_conv2d` with a mathematically
equivalent implementation built from grid_sample (which DOES export), validate
it numerically against the real op, monkeypatch it, then export with the legacy
exporter (grid_sample -> ONNX GridSample at opset 16).
"""
import torch
import torch.nn.functional as F
import torchvision


def grid_deform_conv2d(input, offset, weight, bias=None, stride=1, padding=0, dilation=1, mask=None):
    if isinstance(stride, int): stride = (stride, stride)
    if isinstance(padding, int): padding = (padding, padding)
    if isinstance(dilation, int): dilation = (dilation, dilation)
    B, C, H, W = input.shape
    O, Cg, kh, kw = weight.shape
    sh, sw = stride; ph, pw = padding; dh, dw = dilation
    Ho = (H + 2 * ph - dh * (kh - 1) - 1) // sh + 1
    Wo = (W + 2 * pw - dw * (kw - 1) - 1) // sw + 1
    dev, dt = input.device, input.dtype
    oy = torch.arange(Ho, device=dev, dtype=dt) * sh - ph        # (Ho,)
    ox = torch.arange(Wo, device=dev, dtype=dt) * sw - pw        # (Wo,)
    acc = torch.zeros(B, O, Ho, Wo, device=dev, dtype=dt)
    for a in range(kh):
        for b in range(kw):
            k = a * kw + b
            off_y = offset[:, 2 * k, :, :]                        # (B,Ho,Wo)
            off_x = offset[:, 2 * k + 1, :, :]
            y = oy.view(1, Ho, 1) + a * dh + off_y
            x = ox.view(1, 1, Wo) + b * dw + off_x
            gx = 2 * x / (W - 1) - 1
            gy = 2 * y / (H - 1) - 1
            grid = torch.stack([gx, gy], dim=-1)                  # (B,Ho,Wo,2)
            sampled = F.grid_sample(input, grid, mode="bilinear", padding_mode="zeros", align_corners=True)
            if mask is not None:
                sampled = sampled * mask[:, k:k + 1, :, :]
            acc = acc + torch.einsum("bchw,oc->bohw", sampled, weight[:, :, a, b])
    if bias is not None:
        acc = acc + bias.view(1, O, 1, 1)
    return acc


def _numerical_check():
    torch.manual_seed(0)
    B, C, O = 2, 6, 4
    kh = kw = 3
    H = W = 16
    for pad, dil, st in [(1, 1, 1), (2, 2, 1), (0, 1, 1)]:
        Ho = (H + 2 * pad - dil * (kh - 1) - 1) // st + 1
        Wo = (W + 2 * pad - dil * (kw - 1) - 1) // st + 1
        inp = torch.randn(B, C, H, W)
        offset = torch.randn(B, 2 * kh * kw, Ho, Wo) * 0.7
        mask = torch.sigmoid(torch.randn(B, kh * kw, Ho, Wo))
        weight = torch.randn(O, C, kh, kw)
        bias = torch.randn(O)
        ref = torchvision.ops.deform_conv2d(inp, offset, weight, bias, stride=st, padding=pad, dilation=dil, mask=mask)
        mine = grid_deform_conv2d(inp, offset, weight, bias, stride=st, padding=pad, dilation=dil, mask=mask)
        diff = (ref - mine).abs().max().item()
        print(f"  pad={pad} dil={dil} st={st}: max|diff|={diff:.2e}")
        assert diff < 1e-3, f"deform mismatch {diff}"
    print("numerical check PASSED")


if __name__ == "__main__":
    print("validating grid_sample deform_conv2d…", flush=True)
    _numerical_check()

    # Patch BEFORE importing model code so `from torchvision.ops import deform_conv2d` binds ours.
    torchvision.ops.deform_conv2d = grid_deform_conv2d
    torchvision.ops.deform_conv.deform_conv2d = grid_deform_conv2d
    print("patched torchvision.ops.deform_conv2d", flush=True)

    from transformers import AutoModelForImageSegmentation
    REPO = "ZhengPeng7/BiRefNet-matting"
    OUT = "Models/birefnet-matting.onnx"
    print("loading model…", flush=True)
    model = AutoModelForImageSegmentation.from_pretrained(REPO, trust_remote_code=True).eval().to("cpu")

    # also patch the model's dynamic module namespace if it imported the name directly
    import sys
    for name, mod in list(sys.modules.items()):
        if "birefnet" in name.lower() and hasattr(mod, "deform_conv2d"):
            mod.deform_conv2d = grid_deform_conv2d
            print("patched", name, flush=True)

    class Wrapper(torch.nn.Module):
        def __init__(self, m):
            super().__init__(); self.m = m
        def forward(self, x):
            out = self.m(x)
            return out[-1] if isinstance(out, (list, tuple)) else getattr(out, "logits", out)

    w = Wrapper(model).eval()
    x = torch.randn(1, 3, 1024, 1024)
    with torch.no_grad():
        y = w(x)
        print(f"forward OK shape={tuple(y.shape)} min={float(y.min()):.2f} max={float(y.max()):.2f}", flush=True)
        torch.onnx.export(
            w, x, OUT,
            input_names=["input_image"], output_names=["output_image"],
            opset_version=16, do_constant_folding=True, dynamo=False,
        )
    print("exported ->", OUT, flush=True)
