# SmartClass AI

SmartClass AI imports a lecture analysis JSON and a matching `.pptx` or `.pdf`, combines their content, and builds handwritten-style notes from the uploaded data. Imported lectures do not use a fixed subject or fixed slide content.

## Import workflow

1. Select the language in the header.
2. Open `Add Page`.
3. Select the analysis `.json` file.
4. Select the matching lecture `.pptx` or `.pdf` file. The importer reads slide text and visuals from each presentation page.
5. Click `Generate Notes from JSON + Presentation`.

JSON controls summaries, concepts, chapters, sections, formulas, transcript and timestamps. PPTX or PDF supplies presentation text and page visuals. If a section has a timestamp range, the notes and smartboard views preserve it.

## AI notes endpoint

The browser never contains an API key. The repository includes a server-side Gemini `generateContent` route. Copy `.env.example` to `.env.local`, set `GEMINI_API_KEY`, then run the AI server in a second terminal:

```bash
npm run ai-server
```

The Vite app calls `http://localhost:8787/api/lecture-notes` by default. The API key stays in the server environment, not in a `VITE_*` variable.

The app sends:

```json
{
  "target_language": "hi",
  "target_language_name": "Hindi",
  "preserve_latex": true,
  "input": "analysis JSON object",
  "presentation_pages": [
    { "index": 1, "title": "...", "text": "...", "image_data_url": "..." }
  ]
}
```

The endpoint should return JSON with the generated fields below. All prose must be in `target_language`; keep formulas inside `$...$`, `$$...$$`, `\(...\)` or `\[...\]`.

```json
{
  "title": "...",
  "lecture_overview": "...",
  "simplified_summary": "...",
  "key_concepts": [{ "concept": "...", "explanation": "..." }],
  "technical_terms": [{ "term": "...", "definition": "..." }],
  "sections": [{
    "id": "sec_001",
    "title": "...",
    "summary": "...",
    "handwritten_notes": ["..."]
  }],
  "transcript": [{ "id": "transcript-1", "text": "..." }]
}
```

The server uses Gemini multimodal input and structured JSON output so the model reads the uploaded lecture data and presentation visuals, then returns generated note blocks, concepts, summaries, formulas, diagrams and translations in the requested language. The model chooses the useful note sections from the lecture instead of receiving a fixed BST-style template.

If the AI server is not running or the key is missing, the app still imports and renders the actual JSON/PPTX/PDF content, but it clearly labels the selected-language view as source-derived instead of pretending that translation or AI generation happened.

## Development

```bash
npm install
npm run dev
npm run build
npm run lint
```
