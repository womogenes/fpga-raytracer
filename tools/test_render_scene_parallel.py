from pathlib import Path

from PIL import Image

from render_scene_parallel import compatible_gold_refs


def write_png(path: Path, size: tuple[int, int]) -> None:
    Image.new("RGB", size, color=(0, 0, 0)).save(path)


def test_compatible_gold_refs_filters_by_exact_size(tmp_path: Path) -> None:
    small = tmp_path / "small.png"
    medium = tmp_path / "medium.png"
    large = tmp_path / "large.png"

    write_png(small, (64, 36))
    write_png(medium, (320, 180))
    write_png(large, (640, 360))

    refs = [small, medium, large]
    compatible = compatible_gold_refs(refs, required_size=(320, 180))

    assert compatible == [medium]
