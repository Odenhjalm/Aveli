#!/usr/bin/env python3

import os

import torch

DEVICE_ENV_VAR = "AVELI_INDEX_DEVICE"
SUPPORTED_DEVICES = {"cpu", "cuda"}


def resolve_index_device() -> tuple[str, str]:
    override = (os.getenv(DEVICE_ENV_VAR) or "").strip().lower()
    auto_device = "cuda" if torch.cuda.is_available() else "cpu"

    if not override:
        return auto_device, "auto"

    if override not in SUPPORTED_DEVICES:
        supported = ", ".join(sorted(SUPPORTED_DEVICES))
        raise SystemExit(
            f"FEL: {DEVICE_ENV_VAR} måste vara en av: {supported}"
        )

    if override == "cuda" and auto_device != "cuda":
        raise SystemExit(
            f"FEL: {DEVICE_ENV_VAR}=cuda är satt men CUDA är inte tillgängligt"
        )

    return override, "override"
