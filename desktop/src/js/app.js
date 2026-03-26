// dria desktop — main app logic

// Tauri API
const isTauri = window.__TAURI__ !== undefined;
const invoke = isTauri ? window.__TAURI__.core.invoke : async () => null;
const listen = isTauri ? window.__TAURI__.event.listen : async () => {};

// Init modes
modesManager.init();

// Listen for global shortcut events from Rust
listen('global-shortcut', (event) => {
  const key = event.payload;
  if (key.includes('1')) captureScreen();
  else if (key.includes('2')) submitQuestion();
  else if (key.includes('3')) toggleWindow();
});

// State
const state = {
  messages: [],
  modes: [{ id: 'general', name: 'General', files: [] }],
  activeMode: 'general',
  isStreaming: false,
  isListening: false,
  apiKey: localStorage.getItem('apiKey') || '',
  provider: localStorage.getItem('provider') || 'googleai',
  model: localStorage.getItem('model') || 'gemini-2.5-flash',
};

// DOM
const chatArea = document.getElementById('chatArea');
const emptyState = document.getElementById('emptyState');
const questionInput = document.getElementById('questionInput');
const sendBtn = document.getElementById('sendBtn');
const clearBtn = document.getElementById('clearBtn');
const settingsBtn = document.getElementById('settingsBtn');
const settingsPanel = document.getElementById('settingsPanel');
const settingsClose = document.getElementById('settingsClose');
const micBtn = document.getElementById('micBtn');
const voiceBar = document.getElementById('voiceBar');
const voiceStop = document.getElementById('voiceStop');
const watchBtn = document.getElementById('watchBtn');

// Init voice waves
const voiceWaves = document.getElementById('voiceWaves');
for (let i = 0; i < 20; i++) {
  const bar = document.createElement('div');
  bar.className = 'bar';
  bar.style.animationDelay = `${i * 0.03}s`;
  bar.style.animationDuration = `${0.2 + Math.random() * 0.3}s`;
  voiceWaves.appendChild(bar);
}

// Auto-resize textarea
questionInput.addEventListener('input', () => {
  questionInput.style.height = 'auto';
  questionInput.style.height = Math.min(questionInput.scrollHeight, 54) + 'px';
  sendBtn.disabled = !questionInput.value.trim();
});

// Enter to send, Shift+Enter for newline
questionInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    submitQuestion();
  }
});

// Send button
sendBtn.addEventListener('click', submitQuestion);
sendBtn.disabled = true;

// Clear chat
clearBtn.addEventListener('click', () => {
  state.messages = [];
  renderChat();
});

// Settings
settingsBtn.addEventListener('click', () => settingsPanel.style.display = 'flex');
settingsClose.addEventListener('click', () => settingsPanel.style.display = 'none');

// Settings tabs
document.querySelectorAll('.settings-tabs .tab').forEach(tab => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');
    document.getElementById('tab-' + tab.dataset.tab)?.classList.add('active');
  });
});

// Save API key
document.getElementById('saveApiBtn')?.addEventListener('click', () => {
  state.apiKey = document.getElementById('apiKeyInput').value;
  state.provider = document.getElementById('providerSelect').value;
  state.model = document.getElementById('modelSelect').value;
  localStorage.setItem('apiKey', state.apiKey);
  localStorage.setItem('provider', state.provider);
  localStorage.setItem('model', state.model);
  settingsPanel.style.display = 'none';
});

// Mic toggle
micBtn.addEventListener('click', () => {
  state.isListening = !state.isListening;
  micBtn.classList.toggle('recording', state.isListening);
  micBtn.textContent = state.isListening ? '🔴' : '🎤';
  voiceBar.style.display = state.isListening ? 'flex' : 'none';
  // TODO: Start/stop speech recognition via Tauri command
});

voiceStop.addEventListener('click', () => {
  state.isListening = false;
  micBtn.classList.remove('recording');
  micBtn.textContent = '🎤';
  voiceBar.style.display = 'none';
});

// Watch clipboard toggle
let watching = false;
watchBtn.addEventListener('click', () => {
  watching = !watching;
  watchBtn.classList.toggle('active', watching);
  watchBtn.textContent = watching ? '👁 Watching' : '👁 Auto';
});

// Submit question
async function submitQuestion() {
  const question = questionInput.value.trim();
  if (!question || state.isStreaming) return;

  addMessage('user', question);
  questionInput.value = '';
  questionInput.style.height = 'auto';
  sendBtn.disabled = true;

  if (!state.apiKey) {
    addMessage('assistant', 'No API key set. Go to Settings → AI Model.');
    return;
  }

  state.isStreaming = true;
  const response = await callAI(question);
  state.isStreaming = false;

  addMessage('assistant', response);
}

// Call AI provider
async function callAI(question) {
  try {
    const url = getProviderURL();
    const headers = getProviderHeaders();
    const body = getProviderBody(question);

    const resp = await fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
    const data = await resp.json();

    return extractResponse(data);
  } catch (err) {
    return `Error: ${err.message}`;
  }
}

function getProviderURL() {
  switch (state.provider) {
    case 'googleai':
      return `https://generativelanguage.googleapis.com/v1beta/models/${state.model}:generateContent?key=${state.apiKey}`;
    case 'claude':
      return 'https://api.anthropic.com/v1/messages';
    case 'openai': case 'groq': case 'mistral': case 'openrouter':
      const bases = {
        openai: 'https://api.openai.com/v1',
        groq: 'https://api.groq.com/openai/v1',
        mistral: 'https://api.mistral.ai/v1',
        openrouter: 'https://openrouter.ai/api/v1',
      };
      return `${bases[state.provider]}/chat/completions`;
    case 'ollama':
      return 'http://localhost:11434/v1/chat/completions';
    default:
      return `https://generativelanguage.googleapis.com/v1beta/models/${state.model}:generateContent?key=${state.apiKey}`;
  }
}

function getProviderHeaders() {
  const h = { 'Content-Type': 'application/json' };
  switch (state.provider) {
    case 'claude':
      h['x-api-key'] = state.apiKey;
      h['anthropic-version'] = '2023-06-01';
      break;
    case 'openai': case 'groq': case 'mistral': case 'openrouter':
      h['Authorization'] = `Bearer ${state.apiKey}`;
      break;
  }
  return h;
}

function getProviderBody(question) {
  const systemPrompt = 'You are dria, an intelligent study assistant. Start every response with a short direct answer (max 15 words), then --- on the next line, then the full explanation. Answer in plain text, no markdown.';

  // Add RAG context from knowledge base
  const context = modesManager.buildContext(modesManager.activeId, question);
  const fullQuestion = context ? `Context from study materials:\n${context}\n\nQuestion: ${question}` : question;

  switch (state.provider) {
    case 'googleai':
      return {
        systemInstruction: { parts: [{ text: systemPrompt }] },
        contents: [{ role: 'user', parts: [{ text: fullQuestion }] }],
      };
    case 'claude':
      return {
        model: state.model,
        max_tokens: 2048,
        system: systemPrompt,
        messages: [{ role: 'user', content: fullQuestion }],
      };
    default: // OpenAI-compatible
      return {
        model: state.model,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: fullQuestion },
        ],
      };
  }
}

function extractResponse(data) {
  try {
    if (state.provider === 'googleai') {
      return data.candidates?.[0]?.content?.parts?.[0]?.text || 'No response';
    } else if (state.provider === 'claude') {
      return data.content?.[0]?.text || 'No response';
    } else {
      return data.choices?.[0]?.message?.content || 'No response';
    }
  } catch {
    return 'Failed to parse response';
  }
}

// Chat rendering
function addMessage(role, content) {
  state.messages.push({ role, content, id: Date.now() });
  renderChat();
}

function renderChat() {
  if (state.messages.length === 0) {
    chatArea.innerHTML = '';
    chatArea.appendChild(emptyState);
    emptyState.style.display = 'flex';
    return;
  }

  emptyState.style.display = 'none';
  chatArea.innerHTML = '';

  const recent = state.messages.slice(-20);
  recent.forEach(msg => {
    const div = document.createElement('div');
    div.className = `message ${msg.role}`;

    const bubble = document.createElement('div');
    bubble.className = 'bubble';

    const text = msg.content.length > 500 ? msg.content.slice(0, 500) + '...' : msg.content;
    bubble.textContent = text;

    const copyBtn = document.createElement('button');
    copyBtn.className = 'copy-btn';
    copyBtn.textContent = '📋 Copy';
    copyBtn.onclick = () => {
      navigator.clipboard.writeText(msg.content);
      copyBtn.textContent = '✓ Copied';
      setTimeout(() => copyBtn.textContent = '📋 Copy', 1500);
    };
    bubble.appendChild(copyBtn);

    div.appendChild(bubble);
    chatArea.appendChild(div);
  });

  chatArea.scrollTop = chatArea.scrollHeight;
}

// Load saved messages
const saved = localStorage.getItem('messages');
if (saved) {
  try { state.messages = JSON.parse(saved); } catch {}
}
renderChat();

// Save messages on change
setInterval(() => {
  localStorage.setItem('messages', JSON.stringify(state.messages.slice(-50)));
}, 5000);

// Screen capture
async function captureScreen() {
  try {
    const imageData = await invoke('capture_screen');
    if (imageData) {
      state.capturedImage = imageData;
      // Show preview in chat
      addMessage('user', '[Screenshot captured — press Ctrl+Alt+2 to send]');
      // Update last message with image
      const lastBubble = chatArea.querySelector('.message:last-child .bubble');
      if (lastBubble) {
        const img = document.createElement('img');
        img.src = imageData;
        img.style.maxWidth = '100%';
        img.style.borderRadius = '6px';
        img.style.marginBottom = '4px';
        lastBubble.prepend(img);
      }
    }
  } catch (err) {
    addMessage('assistant', `Capture failed: ${err}`);
  }
}

// Screenshot button
document.getElementById('screenshotBtn').addEventListener('click', captureScreen);

// Toggle window visibility
function toggleWindow() {
  // Handled by Rust tray click — this is for hotkey
  if (isTauri) invoke('toggle_window');
}

// Paste from clipboard
document.getElementById('pasteBtn').addEventListener('click', async () => {
  try {
    const text = isTauri
      ? await invoke('get_clipboard_text')
      : await navigator.clipboard.readText();
    if (text) questionInput.value = text;
    questionInput.dispatchEvent(new Event('input'));
  } catch {}
});

// Question detection patterns (ported from macOS)
function detectQuestionType(text) {
  const lower = text.toLowerCase().trim();
  if (lower.startsWith('true or false')) return 'T/F';
  if (/^[a-d]\.\s/im.test(text) || /\n[a-d]\.\s/im.test(text)) return 'MC';
  if (text.includes('___') || lower.includes('identify the')) return 'ID';
  if (lower.startsWith('explain') || lower.startsWith('discuss') || text.length > 100 && text.includes('?')) return 'Essay';
  return null;
}

// Clipboard monitoring
let clipboardInterval = null;
let lastClipboard = '';
watchBtn.addEventListener('click', () => {
  watching = !watching;
  watchBtn.classList.toggle('active', watching);
  watchBtn.textContent = watching ? '👁 Watching' : '👁 Auto';

  if (watching) {
    clipboardInterval = setInterval(async () => {
      try {
        const text = isTauri
          ? await invoke('get_clipboard_text')
          : await navigator.clipboard.readText();
        if (text && text !== lastClipboard && text.length > 20) {
          lastClipboard = text;
          const type = detectQuestionType(text);
          if (type) {
            questionInput.value = text;
            questionInput.dispatchEvent(new Event('input'));
            // Auto-submit if detection is confident
            submitQuestion();
          }
        }
      } catch {}
    }, 1500);
  } else {
    clearInterval(clipboardInterval);
    clipboardInterval = null;
  }
});

// Voice input via Web Speech API (works in Chrome/Edge, Tauri WebView)
let recognition = null;
if ('webkitSpeechRecognition' in window || 'SpeechRecognition' in window) {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  recognition = new SpeechRecognition();
  recognition.continuous = true;
  recognition.interimResults = true;
  recognition.lang = 'en-US';

  let finalTranscript = '';

  recognition.onresult = (event) => {
    let interim = '';
    for (let i = event.resultIndex; i < event.results.length; i++) {
      if (event.results[i].isFinal) {
        finalTranscript += event.results[i][0].transcript + ' ';
      } else {
        interim += event.results[i][0].transcript;
      }
    }
    questionInput.value = finalTranscript + interim;
    questionInput.dispatchEvent(new Event('input'));
  };

  recognition.onerror = () => {
    state.isListening = false;
    micBtn.classList.remove('recording');
    micBtn.textContent = '🎤';
    voiceBar.style.display = 'none';
  };

  recognition.onend = () => {
    // Restart if still listening (continuous mode)
    if (state.isListening) recognition.start();
  };
}

micBtn.addEventListener('click', () => {
  if (!recognition) {
    addMessage('assistant', 'Speech recognition not available in this browser.');
    return;
  }
  state.isListening = !state.isListening;
  micBtn.classList.toggle('recording', state.isListening);
  micBtn.textContent = state.isListening ? '🔴' : '🎤';
  voiceBar.style.display = state.isListening ? 'flex' : 'none';

  if (state.isListening) {
    recognition.start();
  } else {
    recognition.stop();
  }
});

voiceStop.addEventListener('click', () => {
  state.isListening = false;
  micBtn.classList.remove('recording');
  micBtn.textContent = '🎤';
  voiceBar.style.display = 'none';
  if (recognition) recognition.stop();
});

// ============= File handling =============

function handleFileSelect(event) {
  const files = event.target.files;
  importFiles(files);
}

async function handleFileDrop(event) {
  event.preventDefault();
  chatArea.classList.remove('dragover');
  const files = event.dataTransfer.files;
  importFiles(files);
}

chatArea.addEventListener('dragover', (e) => { e.preventDefault(); chatArea.classList.add('dragover'); });
chatArea.addEventListener('dragleave', () => chatArea.classList.remove('dragover'));
chatArea.addEventListener('drop', handleFileDrop);

async function importFiles(files) {
  for (const file of files) {
    const text = await tools.readFileAsText(file);
    if (text) {
      const chunks = modesManager.addFileText(modesManager.activeId, file.name, text);
      addMessage('assistant', `Imported ${file.name} (${chunks} chunks)`);
      updateModeUI();
    }
  }
}

document.getElementById('fileInput').addEventListener('change', handleFileSelect);

// ============= Flashcards =============

let flashcardData = [];
let flashcardIdx = 0;
let flashcardFlipped = false;

async function showFlashcards() {
  document.getElementById('flashcardModal').style.display = 'flex';
  document.getElementById('flashcardMode').textContent = modesManager.active.name;
  document.getElementById('flashcardText').textContent = 'Generating...';
  flashcardData = await tools.generateFlashcards();
  flashcardIdx = 0;
  flashcardFlipped = false;
  renderFlashcard();
}

function renderFlashcard() {
  if (!flashcardData.length) {
    document.getElementById('flashcardText').textContent = 'No flashcards generated';
    return;
  }
  const card = flashcardData[flashcardIdx];
  document.getElementById('flashcardText').textContent = flashcardFlipped ? card.back : card.front;
  document.getElementById('flashcard').classList.toggle('flipped', flashcardFlipped);
  document.getElementById('flashcardCount').textContent = `${flashcardIdx + 1}/${flashcardData.length}`;
}

function flipCard() { flashcardFlipped = !flashcardFlipped; renderFlashcard(); }
function prevCard() { if (flashcardIdx > 0) { flashcardIdx--; flashcardFlipped = false; renderFlashcard(); } }
function nextCard() { if (flashcardIdx < flashcardData.length - 1) { flashcardIdx++; flashcardFlipped = false; renderFlashcard(); } }

// ============= Mode management =============

function createMode() {
  const name = document.getElementById('newModeName').value.trim();
  if (!name) return;
  modesManager.create(name);
  document.getElementById('newModeName').value = '';
  renderModeSettings();
}

function renderModeSettings() {
  const list = document.getElementById('modesList');
  list.innerHTML = '';
  modesManager.modes.forEach(m => {
    const div = document.createElement('div');
    div.className = 'mode-item';
    div.innerHTML = `<span>${m.icon} ${m.name}</span>`;
    if (m.id !== 'general') {
      const del = document.createElement('button');
      del.className = 'del-btn';
      del.textContent = '✕ Delete';
      del.onclick = () => { modesManager.delete(m.id); renderModeSettings(); };
      div.appendChild(del);
    }
    list.appendChild(div);
  });

  // Show files for active mode
  document.getElementById('modeFilesLabel').textContent = modesManager.active.name;
  const filesList = document.getElementById('modeFilesList');
  filesList.innerHTML = '';
  modesManager.active.files.forEach(f => {
    const div = document.createElement('div');
    div.className = 'file-item';
    div.innerHTML = `<span>📄 ${f.name} (${f.chunkCount} chunks)</span>`;
    const del = document.createElement('button');
    del.className = 'del-btn';
    del.textContent = '✕';
    del.onclick = () => { modesManager.removeFile(modesManager.activeId, f.name); renderModeSettings(); updateModeUI(); };
    div.appendChild(del);
    filesList.appendChild(div);
  });
}

// ============= Two-tier answer + overlay =============

function showAnswerOverlay(text) {
  // Extract short answer (before ---)
  const lines = text.split('\n');
  const sepIdx = lines.findIndex(l => l.trim() === '---');
  const shortAnswer = sepIdx > 0 ? lines.slice(0, sepIdx).join(' ').trim() : text.slice(0, 80);

  document.getElementById('answerShort').textContent = shortAnswer;
  document.getElementById('answerOverlay').style.display = 'flex';

  // Auto-hide after 10s
  setTimeout(() => { document.getElementById('answerOverlay').style.display = 'none'; }, 10000);
}

// Override addMessage to show overlay for assistant messages
const _origAddMessage = addMessage;
addMessage = function(role, content) {
  _origAddMessage(role, content);
  if (role === 'assistant' && content && !content.startsWith('Imported') && !content.startsWith('Error')) {
    showAnswerOverlay(content);
  }
  // Save per-mode chat
  modesManager.saveChat(modesManager.activeId, state.messages);
};

// ============= Settings tab switching =============

document.querySelectorAll('.settings-tabs .tab').forEach(tab => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');
    const target = document.getElementById('tab-' + tab.dataset.tab);
    if (target) target.classList.add('active');
    if (tab.dataset.tab === 'modes') renderModeSettings();
  });
});

// ============= Init =============

// Load settings
document.getElementById('apiKeyInput').value = state.apiKey;
document.getElementById('providerSelect').value = state.provider;
document.getElementById('modelSelect').value = state.model;

// Load per-mode chat
state.messages = modesManager.loadChat(modesManager.activeId);
renderChat();
updateModeUI();
document.getElementById('modeNameDisplay').textContent = modesManager.active.name;
