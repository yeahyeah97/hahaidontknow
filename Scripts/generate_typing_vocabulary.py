"""Regenerate the CC BY-SA data subset; requires wordfreq==3.1.1."""
from pathlib import Path
from importlib.metadata import distribution
from wordfreq import top_n_list, zipf_frequency

output = Path(__file__).resolve().parents[1] / "Shared" / "Resources" / "TypingVocabulary"
output.mkdir(parents=True, exist_ok=True)
for language in ("it", "en"):
    words = [word for word in top_n_list(language, 12000)
             if 2 <= len(word) <= 24 and all(c.isalpha() or c in "'’" for c in word)][:8000]
    (output / (language + ".tsv")).write_text(
        "".join(f"{word}\t{zipf_frequency(word, language):.2f}\n" for word in words), encoding="utf-8")
metadata = distribution("wordfreq").read_text("METADATA")
section = metadata[metadata.index("## License"):metadata.index("## Citation")]
(output / "WORD_FREQUENCY_NOTICE.txt").write_text(
    "Milazy frequency vocabulary data\n\n"
    "Derived from wordfreq 3.1.1 by Robyn Speer (2022), https://github.com/rspeer/wordfreq .\n"
    "Changes: IT/EN lists restricted to 8,000 alphabetic tokens per language, "
    "2–24 characters; Zipf frequencies rounded to two decimals.\n"
    "These derived data files are distributed under CC BY-SA 4.0. "
    "This attribution applies to vocabulary data; wordfreq software is not shipped.\n\n"
    + section, encoding="utf-8")
