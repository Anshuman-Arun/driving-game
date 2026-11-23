"""Generate a seamless 2048x2048 tileable water normal map using 2D FFT."""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(r"c:\Users\anshu\Documents\Coding\Driving-Game\driving-game")
OUT_PATH = ROOT / "assets" / "forza_env" / "textures" / "water" / "normal.png"


def generate_water_normal(size: int = 2048, seed: int = 42, strength: float = 2.6) -> Image.Image:
    rng = np.random.default_rng(seed)

    # Frequency grid for seamless periodic tiling
    fx = np.fft.fftfreq(size) * size
    fy = np.fft.fftfreq(size) * size
    kx, ky = np.meshgrid(fx, fy)
    k = np.sqrt(kx**2 + ky**2)
    k_safe = np.maximum(k, 1e-6)

    # Multi-octave directional + isotropic ocean/lake wave spectrum
    # Favor mid-to-high frequency ripples suitable for a calm alpine lake
    spectrum = np.zeros_like(k)
    band1 = np.exp(-0.5 * ((np.log2(k_safe) - 4.0) / 1.4) ** 2) / (k_safe ** 1.35)
    band2 = 0.55 * np.exp(-0.5 * ((np.log2(k_safe) - 6.2) / 1.2) ** 2) / (k_safe ** 1.15)
    spectrum = (band1 + band2) * (k > 2.0) * (k < size * 0.35)

    # Directional wind bias (gentle breeze)
    dir_bias = 0.65 + 0.35 * (np.abs(kx * 0.8 + ky * 0.6) / k_safe) ** 2
    amp = np.sqrt(spectrum * dir_bias)

    phase = rng.uniform(0, 2 * np.pi, size=(size, size))
    noise_fft = amp * (np.cos(phase) + 1j * np.sin(phase))

    height = np.fft.ifft2(noise_fft).real
    height = (height - height.mean()) / (height.std() + 1e-8)

    # Periodic finite differences for seamless normals
    dh_dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * strength
    dh_dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * strength

    nx = -dh_dx
    ny = -dh_dy
    nz = np.ones_like(height)
    norm = np.sqrt(nx**2 + ny**2 + nz**2)
    nx /= norm
    ny /= norm
    nz /= norm

    # OpenGL tangent-space normal map: R=X, G=Y, B=Z in [0, 255]
    rgb = np.stack([
        np.clip((nx * 0.5 + 0.5) * 255.0, 0, 255),
        np.clip((ny * 0.5 + 0.5) * 255.0, 0, 255),
        np.clip((nz * 0.5 + 0.5) * 255.0, 0, 255),
    ], axis=-1).astype(np.uint8)
    return Image.fromarray(rgb, mode="RGB")


def main():
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    img = generate_water_normal(2048)
    img.save(OUT_PATH, optimize=True)
    print(f"Generated {OUT_PATH.relative_to(ROOT)} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    main()
