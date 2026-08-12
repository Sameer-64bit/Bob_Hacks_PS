import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const serverDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.resolve(serverDirectory, '..');

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return;
  const lines = fs.readFileSync(filePath, 'utf8').split(/\r?\n/);
  lines.forEach((line) => {
    const match = line.match(/^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (!match || process.env[match[1]]) return;
    process.env[match[1]] = match[2].replace(/^['"]|['"]$/g, '');
  });
}

loadEnvFile(path.join(projectDirectory, '.env'));
loadEnvFile(path.join(projectDirectory, '.env.local'));

const port = Number(process.env.AI_SERVER_PORT || 8787);
const model = process.env.GEMINI_MODEL || 'gemini-3.6-flash';

const notesSchema = {
  type: 'object',
  additionalProperties: false,
  properties: {
    title: { type: 'string' },
    lecture_overview: { type: 'string' },
    simplified_summary: { type: 'string' },
    key_concepts: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          concept: { type: 'string' },
          explanation: { type: 'string' }
        },
        required: ['concept', 'explanation']
      }
    },
    technical_terms: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          term: { type: 'string' },
          definition: { type: 'string' }
        },
        required: ['term', 'definition']
      }
    },
    note_sections: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          id: { type: 'string' },
          title: { type: 'string' },
          kind: { type: 'string' },
          body: { type: 'string' },
          bullets: { type: 'array', items: { type: 'string' } },
          formula: { type: 'string' },
          diagram_description: { type: 'string' }
        },
        required: ['id', 'title', 'kind', 'body', 'bullets', 'formula', 'diagram_description']
      }
    },
    sections: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          id: { type: 'string' },
          title: { type: 'string' },
          summary: { type: 'string' },
          handwritten_notes: { type: 'array', items: { type: 'string' } },
          diagram_explanation: { type: 'string' },
          diagram_key_takeaways: { type: 'array', items: { type: 'string' } }
        },
        required: ['id', 'title', 'summary', 'handwritten_notes', 'diagram_explanation', 'diagram_key_takeaways']
      }
    },
    transcript: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          id: { type: 'string' },
          text: { type: 'string' }
        },
        required: ['id', 'text']
      }
    }
  },
  required: ['title', 'lecture_overview', 'simplified_summary', 'key_concepts', 'technical_terms', 'note_sections', 'sections', 'transcript']
};

function sendJson(response, status, payload) {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS'
  });
  response.end(JSON.stringify(payload));
}

function readRequestBody(request) {
  return new Promise((resolve, reject) => {
    let body = '';
    request.on('data', (chunk) => {
      body += chunk;
      if (body.length > 80 * 1024 * 1024) reject(new Error('Request is too large.'));
    });
    request.on('end', () => {
      try {
        resolve(JSON.parse(body || '{}'));
      } catch {
        reject(new Error('Request body must be valid JSON.'));
      }
    });
    request.on('error', reject);
  });
}

function collectGeminiResponseText(payload) {
  return (payload.candidates || [])
    .flatMap((candidate) => candidate.content?.parts || [])
    .map((part) => part.text)
    .filter((text) => typeof text === 'string')
    .join('')
    .trim();
}

function parseJsonOutput(text) {
  const cleaned = text.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '');
  return JSON.parse(cleaned);
}

async function callGemini({ systemPrompt, userParts, schema }) {
  if (!process.env.GEMINI_API_KEY) {
    throw new Error('GEMINI_API_KEY is not configured on the AI server.');
  }

  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
    method: 'POST',
    headers: {
      'x-goog-api-key': process.env.GEMINI_API_KEY,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      system_instruction: {
        parts: [{ text: systemPrompt }]
      },
      contents: [{
        role: 'user',
        parts: userParts
      }],
      generationConfig: {
        responseMimeType: 'application/json',
        responseJsonSchema: schema
      }
    })
  });

  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error?.message || `Gemini API returned HTTP ${response.status}.`);
  }

  const text = collectGeminiResponseText(payload);
  if (!text) {
    const reason = payload.promptFeedback?.blockReason || payload.candidates?.[0]?.finishReason;
    throw new Error(reason ? `Gemini returned no text output (${reason}).` : 'Gemini returned no text output.');
  }
  return parseJsonOutput(text);
}

function presentationText(pages = []) {
  return pages.map((page) => ({
    index: page.index,
    title: page.title,
    text: page.text
  }));
}

function imageInputs(pages = []) {
  return pages
    .filter((page) => typeof page.image_data_url === 'string' && page.image_data_url.startsWith('data:image/'))
    .slice(0, 12)
    .map((page) => {
      const match = page.image_data_url.match(/^data:([^;,]+)(?:;[^,]*)?;base64,(.+)$/s);
      if (!match) return null;
      return {
        inline_data: {
          mime_type: match[1],
          data: match[2]
        }
      };
    })
    .filter(Boolean);
}

async function handleNotes(body) {
  const targetLanguage = body.target_language_name || body.target_language || 'English';
  const source = JSON.stringify({
    analysis_json: body.input || {},
    presentation_pages: presentationText(body.presentation_pages || [])
  });
  const systemPrompt = [
    'You are the lecture-notes generator for a classroom application.',
    `Write every generated sentence in ${targetLanguage}. Do not mix languages except for source terms and mathematical notation.`,
    'Use only facts present in the supplied JSON, presentation text, and presentation images. If information is missing, say so instead of inventing it.',
    'Create useful handwritten-style study notes. The application will render your note_sections, so choose their number, order, titles and kinds based on the lecture. Do not use a fixed subject or fixed template.',
    'For every item in sections, write summary as a short explanation of what that slide means and why it matters to a student. Write handwritten_notes as 3 to 6 concise analytical takeaways derived from that slide; explain relationships, purpose, cause/effect or practical meaning instead of repeating headings or copying OCR lines.',
    'Do not copy slide text line-by-line into handwritten_notes. Do not return raw OCR, UI labels, repeated punctuation, star/rating annotations, or meaningless fragments. If a slide is mostly a list, group the list into meaningful categories and explain the overall idea.',
    'Every handwritten_notes item must be a complete, understandable explanatory sentence. Do not start notes with words such as covers, lists, topics, slide, or figure; explain the underlying concept directly.',
    'Return exactly one sections item for every input analysis_json.sections item, preserve each source section id exactly, and do not omit slides. The sections array is the source for the Whiteboard AI Slide Analysis panel.',
    'For every slide section, return diagram_explanation and diagram_key_takeaways as an empty string and empty array when no diagram is present; otherwise translate and explain the diagram in the requested language.',
    'Possible kinds are overview, definition, comparison, process, formula, example, checklist, diagram, summary and custom. Use only kinds that fit the lecture.',
    'Use an empty string for formula or diagram_description when that field is not applicable.',
    'Preserve all mathematical notation in LaTeX delimiters such as $...$, $$...$$, \\( ... \\) or \\[ ... \\].',
    'Return only the requested structured JSON.'
  ].join(' ');
  const userParts = [
    { text: `SOURCE LECTURE DATA:\n${source}` },
    ...imageInputs(body.presentation_pages || [])
  ];
  return callGemini({ systemPrompt, userParts, schema: notesSchema });
}

async function handleQa(body) {
  const targetLanguage = body.target_language_name || body.target_language || 'English';
  const source = JSON.stringify(body.lecture || {});
  const history = JSON.stringify(body.history || []);
  const systemPrompt = [
    'You are a grounded lecture tutor.',
    `Answer entirely in the requested language: ${targetLanguage}.`,
    'Use only the uploaded lecture context. If the answer is not supported by it, clearly say that the lecture data does not contain the answer.',
    'Return a JSON object with one string property named answer.'
  ].join(' ');
  const qaSchema = {
    type: 'object',
    additionalProperties: false,
    properties: { answer: { type: 'string' } },
    required: ['answer']
  };
  const result = await callGemini({
    systemPrompt,
    userParts: [{ text: `LECTURE CONTEXT:\n${source}\nCHAT HISTORY:\n${history}\nQUESTION:\n${body.query || ''}` }],
    schema: qaSchema
  });
  return { answer: result.answer };
}

const server = http.createServer(async (request, response) => {
  if (request.method === 'GET' && request.url === '/health') {
    return sendJson(response, 200, { ok: true, aiConfigured: Boolean(process.env.GEMINI_API_KEY), model });
  }
  if (request.method === 'OPTIONS') return sendJson(response, 204, {});
  if (request.method !== 'POST') return sendJson(response, 404, { error: 'Not found.' });

  try {
    const body = await readRequestBody(request);
    const result = request.url === '/api/lecture-qa'
      ? await handleQa(body)
      : request.url === '/api/lecture-notes'
        ? await handleNotes(body)
        : null;
    if (!result) return sendJson(response, 404, { error: 'Not found.' });
    return sendJson(response, 200, result);
  } catch (error) {
    return sendJson(response, 500, { error: error instanceof Error ? error.message : 'AI service failed.' });
  }
});

server.on('error', (error) => {
  if (error?.code === 'EADDRINUSE') {
    console.log(`SmartClass AI server is already running on http://localhost:${port}. Use the existing process.`);
    return;
  }

  console.error('SmartClass AI server could not start:', error);
  process.exitCode = 1;
});

server.listen(port, () => {
  console.log(`SmartClass AI server listening on http://localhost:${port}`);
});
