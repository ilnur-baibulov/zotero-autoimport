# zotero-autoimport

Bibliographic metadata for bare files. Drop a PDF, DjVu or EPUB into a
folder; the importer works out what it is — authors, title, publisher, year,
volume, ISBN or journal and DOI — and creates a Zotero item with these fields
and the file attached. It reads the metadata from the document itself: from
Crossref when the first pages carry a DOI, otherwise by giving the title
pages and the imprint to a language model.

This covers files that Zotero's own "Retrieve Metadata" and browser connector
cannot identify: books from shadow libraries, OCR'd scans, articles from sites
with no Zotero translator (e.g. mathnet.ru), Russian-language books whose
ISBNs are missing from the usual catalogues.

It runs on macOS as a watched folder (`~/Downloads/to-zotero` by default).
Imported items are tagged `auto-import` and filed into one collection (or one
per topic); a notification says what was added.

> **Note.** This is a vibe-coded personal tool built around my own workflow. Feel free to use, adapt or fork it.

## How metadata are found

For each file:

1. **DOI.** A DOI on the first two pages is looked up in Crossref. The record
   is accepted only if at least 60% of the words of its title (words longer
   than 3 letters) occur on those pages; this rejects DOIs of cited works.
2. **Otherwise, a model reads the document.** The text of the first 6 and the
   last 3 pages goes to a language model (see [Model](#model)). It returns
   Zotero fields: item type, creators, title, volume, publisher, place, year,
   ISBN, journal, pages, the printed abstract or annotation (verbatim), and
   for translations the year of the original (stored in Extra as
   `original-date: 1867`, which citation styles and Better BibTeX read). For
   EPUB the OPF metadata and the first chapters are used. The prompt asks for
   names and titles in the script of the document, the imprint data of the
   edition at hand, only the volume's own ISBN, and no technical staff
   (proofreaders, designers) among the creators; it ignores advertisement
   pages at the end of a book.
   For a scan without a text layer, the 9 pages are rendered to images for the
   model to read; if that fails, the importer tries `ocrmypdf` on those pages
   (when installed), then the file name, and finally imports the file under its
   bare name so nothing is lost.
3. **Topic** (only if topics are configured). The same call returns one of
   your topics, which picks the collection.

All fields are cleaned before saving: HTML/JATS/MathML markup is stripped,
languages become ISO 639-1 codes (`ru`, `en`), and «Издательство «X»» becomes
`X`.

If the library already has an item with the same title, volume and (when
both are known) year, the file is still imported, with an extra tag
`possible-duplicate`; Zotero's *Duplicate Items* view merges the two if they
really are the same.

## What happens to the file

| outcome | file moves to | Zotero |
|---|---|---|
| imported | `to-zotero/processed/` | new item + attachment (+ `possible-duplicate` tag) |
| error | `to-zotero/failed/` | unchanged |

Every run is logged to `~/Library/Logs/zotero-autoimport.log`.

## Requirements

- macOS, Zotero 7 or later, running (the importer talks to it on
  `localhost:23119`; if Zotero is closed, files wait in the folder).
- Python 3.9+, standard library only.
- A model CLI configured in `config.env`, see [Model](#model).
- Poppler: `brew install poppler`. Optional: `brew install djvulibre` for DjVu,
  and `brew install ocrmypdf` (with `tesseract-lang`) as an OCR fallback for
  PDF scans.

## Install

```sh
git clone https://github.com/ilnur-baibulov/zotero-autoimport
cd zotero-autoimport
cp config.env.example config.env   # set ZAI_LLM_CMD and your collection
./install.sh                       # or ./install.sh /path/to/another/folder
```

`install.sh` writes a launchd agent to
`~/Library/LaunchAgents/local.zotero-autoimport.plist`. launchd starts the
script whenever the folder changes; between runs nothing is running. On the
first run macOS may ask whether `python3` may access the Downloads folder.

`./uninstall.sh` removes the agent. A single file can be imported by hand
with `./zotero_autoimport.py file.pdf` (the file is then left where it is).

## Settings

Put them in `config.env` next to the script (copy `config.env.example`; the
file is ignored by git), or set them in the environment, which takes
precedence. The script reads `config.env` on every run, so no reinstall is
needed. `ZAI_INBOX` is the exception: the watched folder is fixed at install
time, so pass it to `install.sh` instead.

| variable | default | meaning |
|---|---|---|
| `ZAI_INBOX` | `~/Downloads/to-zotero` | drop folder |
| `ZAI_COLLECTION` | `Inbox` | collection for imported items |
| `ZAI_TOPIC_<name>` | none | optional topic, see below |
| `ZAI_TAG` | `auto-import` | tag put on every imported item |
| `ZAI_DUP_TAG` | `possible-duplicate` | extra tag when a likely twin exists |
| `ZAI_LLM_CMD` | none (required) | model command, see [Model](#model) |
| `ZAI_OCR_LANG` | installed Tesseract langs | languages passed to `ocrmypdf -l` |
| `ZAI_CROSSREF_MAILTO` | empty | your e-mail for Crossref's polite pool |

Collections are matched by name; create them in Zotero first. If a collection
does not exist, the item lands in the one currently selected in Zotero.

**Topics.** To split imports by subject, add one line per topic:

```sh
ZAI_TOPIC_MATH=Inbox math | mathematics, mathematical physics, theoretical CS
ZAI_TOPIC_NONFIC=Inbox nonfiction | history, philosophy, essays
```

The part before `|` is the collection, the part after it tells the model what
belongs there. An item that fits no topic goes to `ZAI_COLLECTION`.

## Model

Set `ZAI_LLM_CMD` in `config.env` to any command that prints the model's reply.
`{prompt}` in the command is replaced by the prompt; without it, the prompt is
sent on stdin.

```sh
ZAI_LLM_CMD=agy --model gemini-3.8-flash-low -p {prompt}                 # Antigravity CLI
ZAI_LLM_CMD=claude -p --model haiku --no-session-persistence --allowedTools Read   # Claude Code
ZAI_LLM_CMD=copilot -s -p {prompt}                                       # GitHub Copilot CLI
ZAI_LLM_CMD=codex exec -m gpt-6-luna -c model_reasoning_effort="low" --skip-git-repo-check --ephemeral   # OpenAI Codex CLI
ZAI_LLM_CMD=ollama run qwen2.5:14b                                       # local model via Ollama
```

`claude`, `agy`, `copilot` and `codex` were tested on Russian and English
books; the `ollama` line is an untested example.

**Pin a small model.** The task is extraction from a few pages; a small model
does it as well as a large one. Most CLIs use a large default unless told
otherwise — for `agy` that is Gemini Flash (High), for Copilot it depends on
your plan — so pass their `--model` flag a small model your account offers
(`agy models` lists them). The reply must contain one JSON object; anything
around it is ignored.

## How it writes to Zotero

Through the endpoints of Zotero's browser connector (`/connector/saveItems`,
`/connector/updateSession`, `/connector/saveAttachment`): no API key, no
authorization dialog, and the item goes through Zotero's normal save
pipeline, so it syncs like anything saved from the browser. These endpoints
are not a documented public API and may change between Zotero versions.

## Limitations

- Small local models handle the text case less reliably than hosted ones,
  especially with non-English imprints.
- The model sees 9 pages. If the imprint is elsewhere (common in scans), the
  year or publisher stays empty.
- Model output can be wrong in details: swapped first and last names, year of
  the original instead of the translation. The `auto-import` tag is there for
  a quick review.
- Duplicate detection compares title, volume and year only; a DOI or ISBN
  match under a different title goes unnoticed.

## License

MIT
