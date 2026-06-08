import argparse
import asyncio
import os
import sys
import uuid


def file_has_audio(path, min_bytes):
    return bool(path and os.path.exists(path) and os.path.getsize(path) >= min_bytes)


def read_text_file(path):
    if not path:
        return ""
    with open(path, "r", encoding="utf-8-sig") as handle:
        return handle.read().strip()


async def write_edge_tts(text, output_path, voice):
    import edge_tts

    communicate = edge_tts.Communicate(text=text, voice=voice)
    await communicate.save(output_path)


def patch_torch_load_for_rvc():
    import torch

    original_load = torch.load

    def compatible_load(*args, **kwargs):
        kwargs.setdefault("weights_only", False)
        return original_load(*args, **kwargs)

    torch.load = compatible_load


def run_conversion(args):
    patch_torch_load_for_rvc()

    from rvc_python.infer import RVCInference

    rvc = RVCInference(
        device=args.device,
        model_path=args.model,
        index_path=args.index or "",
        version=args.version,
    )
    rvc.set_params(
        f0method=args.method,
        f0up_key=args.pitch,
        index_rate=args.index_rate,
        filter_radius=args.filter_radius,
        resample_sr=args.resample_sr,
        rms_mix_rate=args.rms_mix_rate,
        protect=args.protect,
    )
    rvc.infer_file(args.input_audio, args.output)


def main():
    parser = argparse.ArgumentParser(description="Notifu RVC speech wrapper")
    parser.add_argument("--text-file", default="")
    parser.add_argument("--fallback-input", default="")
    parser.add_argument("--output", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--index", default="")
    parser.add_argument("--pitch", type=int, default=0)
    parser.add_argument("--voice", default="id-ID-GadisNeural")
    parser.add_argument("--device", default="cpu:0")
    parser.add_argument("--method", default="harvest", choices=["harvest", "crepe", "rmvpe", "pm"])
    parser.add_argument("--version", default="v2", choices=["v1", "v2"])
    parser.add_argument("--index-rate", type=float, default=0.6)
    parser.add_argument("--filter-radius", type=int, default=3)
    parser.add_argument("--resample-sr", type=int, default=0)
    parser.add_argument("--rms-mix-rate", type=float, default=0.25)
    parser.add_argument("--protect", type=float, default=0.5)
    parser.add_argument("--min-output-bytes", type=int, default=2048)
    args = parser.parse_args()

    output_dir = os.path.dirname(os.path.abspath(args.output))
    os.makedirs(output_dir, exist_ok=True)

    text = read_text_file(args.text_file)
    edge_audio = os.path.join(output_dir, f"notifu-edge-{uuid.uuid4().hex}.mp3")

    args.input_audio = ""
    if text:
        try:
            asyncio.run(write_edge_tts(text, edge_audio, args.voice))
            if file_has_audio(edge_audio, 1024):
                args.input_audio = edge_audio
                print(f"Base TTS: {args.voice}")
        except Exception as exc:
            print(f"Edge TTS failed, using fallback input if available: {exc}", file=sys.stderr)

    if not args.input_audio and file_has_audio(args.fallback_input, 1024):
        args.input_audio = args.fallback_input
        print("Base TTS: fallback Windows SAPI")

    if not args.input_audio:
        raise RuntimeError("No usable base audio was produced.")

    run_conversion(args)

    if not file_has_audio(args.output, args.min_output_bytes):
        raise RuntimeError(f"RVC output is missing or too small: {args.output}")

    print(f"RVC output: {args.output}")


if __name__ == "__main__":
    main()
