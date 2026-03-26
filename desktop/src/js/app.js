// dria desktop — main app logic

// Tauri API
const isTauri = window.__TAURI__ !== undefined;
const invoke = isTauri ? window.__TAURI__.core.invoke : async () => null;
const listen = isTauri ? window.__TAURI__.event.listen : async () => {};

// Init modes
modesManager.init();

// Global shortcut listener is set up later in the hotkeys section
// (after all functions are defined, so captureScreen/submitQuestion/toggleWindow exist)

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

// Mic toggle — handled in voice input section below
// voiceStop early handler — handled in voice input section below

// Watch clipboard toggle — handled in clipboard monitoring section below
let watching = false;

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
  setTrayStatus('processing');
  const response = await callAI(question);
  state.isStreaming = false;
  setTrayStatus('ready');

  addMessage('assistant', response);

  // Analytics: count query
  if (typeof analytics !== 'undefined') analytics.increment('totalQueries');

  // Return to idle after a brief delay
  setTimeout(() => setTrayStatus('idle'), 3000);
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
      const mode = localStorage.getItem('copyMode') || 'short';
      let textToCopy = msg.content;
      if (mode === 'short') {
        const lines = msg.content.split('\n');
        const sepIdx = lines.findIndex(l => l.trim() === '---');
        if (sepIdx > 0) textToCopy = lines.slice(0, sepIdx).join(' ').trim();
      }
      navigator.clipboard.writeText(textToCopy);
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
    setTrayStatus('captured');
    const imageData = await invoke('capture_screen');
    if (imageData) {
      state.capturedImage = imageData;
      // Analytics: count screenshot
      if (typeof analytics !== 'undefined') analytics.increment('screenshots');
      // Show preview in chat
      const sendKey = localStorage.getItem('hotkeySend') || '2';
      addMessage('user', `[Screenshot captured — press Ctrl+Alt+${sendKey} to send]`);
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
    setTrayStatus('error');
    addMessage('assistant', `Capture failed: ${err}`);
  }
  setTimeout(() => setTrayStatus('idle'), 2000);
}

// Screenshot button
document.getElementById('screenshotBtn').addEventListener('click', captureScreen);

// Toggle window visibility
function toggleWindow() {
  // Respect lock popover setting
  if (localStorage.getItem('lockPopover') === 'true') return;
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
            // Analytics: count auto-answer
            if (typeof analytics !== 'undefined') analytics.increment('autoAnswers');
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
    setTrayStatus('recording');
  } else {
    recognition.stop();
    setTrayStatus('idle');
  }
});

voiceStop.addEventListener('click', () => {
  state.isListening = false;
  micBtn.classList.remove('recording');
  micBtn.textContent = '🎤';
  voiceBar.style.display = 'none';
  if (recognition) recognition.stop();
  setTrayStatus('idle');
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
      // Analytics: count file import
      if (typeof analytics !== 'undefined') analytics.increment('filesImported');
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

// ============= Feature: Stealth / Ghost mode =============

const stealthSlider = document.getElementById('stealthSlider');
const stealthValue = document.getElementById('stealthValue');
const answerOverlay = document.getElementById('answerOverlay');

function applyStealthOpacity(val) {
  const opacity = parseFloat(val);
  answerOverlay.style.opacity = opacity;
  // Apply to all chat message bubbles
  document.querySelectorAll('.message .bubble').forEach(b => b.style.opacity = opacity);
  stealthValue.textContent = opacity.toFixed(1);
  stealthSlider.value = opacity;
  localStorage.setItem('stealthOpacity', opacity);
}

stealthSlider.addEventListener('input', (e) => applyStealthOpacity(e.target.value));

document.querySelectorAll('.stealth-preset').forEach(btn => {
  btn.addEventListener('click', () => applyStealthOpacity(btn.dataset.val));
});

// Load saved stealth value
const savedStealth = localStorage.getItem('stealthOpacity') || '1.0';
applyStealthOpacity(savedStealth);

// Hook into renderChat to re-apply opacity after messages render
const _origRenderChat = renderChat;
renderChat = function() {
  _origRenderChat();
  const opacity = parseFloat(localStorage.getItem('stealthOpacity') || '1.0');
  if (opacity < 1.0) {
    document.querySelectorAll('.message .bubble').forEach(b => b.style.opacity = opacity);
  }
};

// ============= Feature: Lock popover =============

const lockPopoverToggle = document.getElementById('lockPopoverToggle');
lockPopoverToggle.checked = localStorage.getItem('lockPopover') === 'true';

lockPopoverToggle.addEventListener('change', () => {
  localStorage.setItem('lockPopover', lockPopoverToggle.checked);
  if (isTauri) invoke('set_lock_popover', { locked: lockPopoverToggle.checked });
});

// Sync lock state to Rust on startup
if (isTauri && lockPopoverToggle.checked) {
  invoke('set_lock_popover', { locked: true });
}

// ============= Feature: Configurable copy mode =============

const copyModeSelect = document.getElementById('copyModeSelect');
copyModeSelect.value = localStorage.getItem('copyMode') || 'short';
copyModeSelect.addEventListener('change', () => {
  localStorage.setItem('copyMode', copyModeSelect.value);
});

// ============= Feature: Analytics =============

const analytics = {
  _key: 'driaAnalytics',
  _defaults: { totalQueries: 0, screenshots: 0, autoAnswers: 0, filesImported: 0 },

  load() {
    try {
      return { ...this._defaults, ...JSON.parse(localStorage.getItem(this._key) || '{}') };
    } catch { return { ...this._defaults }; }
  },
  save(data) { localStorage.setItem(this._key, JSON.stringify(data)); },
  increment(key) {
    const data = this.load();
    data[key] = (data[key] || 0) + 1;
    this.save(data);
    this.render();
  },
  reset() {
    this.save({ ...this._defaults });
    this.render();
  },
  render() {
    const data = this.load();
    document.getElementById('statQueries').textContent = data.totalQueries;
    document.getElementById('statScreenshots').textContent = data.screenshots;
    document.getElementById('statAutoAnswers').textContent = data.autoAnswers;
    document.getElementById('statFiles').textContent = data.filesImported;
  }
};

document.getElementById('resetStatsBtn').addEventListener('click', () => analytics.reset());
analytics.render();

// ============= Feature: Debug log export =============

document.getElementById('exportLogsBtn').addEventListener('click', () => {
  const data = analytics.load();
  const modes = modesManager.modes;
  const totalFiles = modes.reduce((sum, m) => sum + m.files.length, 0);
  const log = [
    'dria Desktop — Debug Log',
    '========================',
    `Date: ${new Date().toISOString()}`,
    `Version: 1.0.0`,
    `Provider: ${state.provider}`,
    `Model: ${state.model}`,
    `API Key: ${state.apiKey ? 'set (' + state.apiKey.length + ' chars)' : 'not set'}`,
    `Modes: ${modes.length}`,
    `Files across modes: ${totalFiles}`,
    `Messages in current chat: ${state.messages.length}`,
    `Browser: ${navigator.userAgent}`,
    `Platform: ${navigator.platform}`,
    `Tauri: ${isTauri ? 'yes' : 'no'}`,
    `Stealth opacity: ${localStorage.getItem('stealthOpacity') || '1.0'}`,
    `Lock popover: ${localStorage.getItem('lockPopover') || 'false'}`,
    `Copy mode: ${localStorage.getItem('copyMode') || 'short'}`,
    '',
    'Analytics:',
    `  Total queries: ${data.totalQueries}`,
    `  Screenshots: ${data.screenshots}`,
    `  Auto answers: ${data.autoAnswers}`,
    `  Files imported: ${data.filesImported}`,
    '',
    'Modes:',
    ...modes.map(m => `  ${m.icon} ${m.name} (${m.files.length} files)`),
  ].join('\n');

  const blob = new Blob([log], { type: 'text/plain' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `dria-debug-${Date.now()}.txt`;
  a.click();
  URL.revokeObjectURL(url);
});

// ============= Feature: Bug report button =============

document.getElementById('reportBugBtn').addEventListener('click', () => {
  const url = 'https://github.com/CelestialBrain/dria/issues/new';
  if (isTauri) {
    window.__TAURI__?.shell?.open(url);
  } else {
    window.open(url, '_blank');
  }
});

// ============= Feature: Launch at login =============

const launchAtLoginToggle = document.getElementById('launchAtLoginToggle');

async function loadAutoStartState() {
  if (!isTauri) return;
  try {
    const enabled = await invoke('get_autostart');
    launchAtLoginToggle.checked = enabled;
  } catch {}
}

launchAtLoginToggle.addEventListener('change', async () => {
  if (!isTauri) return;
  try {
    await invoke('set_autostart', { enabled: launchAtLoginToggle.checked });
  } catch (err) {
    console.error('Failed to set autostart:', err);
    launchAtLoginToggle.checked = !launchAtLoginToggle.checked;
  }
});

loadAutoStartState();

// ============= Feature: Configurable Hotkeys =============

const hotkeyCapture = document.getElementById('hotkeyCapture');
const hotkeySend = document.getElementById('hotkeySend');
const hotkeyToggle = document.getElementById('hotkeyToggle');
const hotkeyHelp = document.getElementById('hotkeyHelp');

// Load saved hotkeys
const savedCapture = localStorage.getItem('hotkeyCapture') || '1';
const savedSend = localStorage.getItem('hotkeySend') || '2';
const savedToggle = localStorage.getItem('hotkeyToggle') || '3';
hotkeyCapture.value = savedCapture;
hotkeySend.value = savedSend;
hotkeyToggle.value = savedToggle;

function updateHotkeyHelp() {
  const c = hotkeyCapture.value;
  const s = hotkeySend.value;
  const t = hotkeyToggle.value;
  if (hotkeyHelp) {
    hotkeyHelp.innerHTML =
      `Ctrl+Alt+${c} to capture screen<br>` +
      `Ctrl+Alt+${s} to send to AI<br>` +
      `Ctrl+Alt+${t} to toggle chat<br><br>` +
      `Drop files here to add to knowledge base`;
  }
}
updateHotkeyHelp();

document.getElementById('saveHotkeysBtn').addEventListener('click', async () => {
  const c = hotkeyCapture.value;
  const s = hotkeySend.value;
  const t = hotkeyToggle.value;
  localStorage.setItem('hotkeyCapture', c);
  localStorage.setItem('hotkeySend', s);
  localStorage.setItem('hotkeyToggle', t);
  updateHotkeyHelp();

  if (isTauri) {
    try {
      await invoke('update_hotkeys', { capture: c, send: s, toggle: t });
    } catch (err) {
      console.error('Failed to update hotkeys:', err);
    }
  }
});

// Update global-shortcut listener to use configurable keys
listen('global-shortcut', (event) => {
  const key = event.payload;
  const ck = localStorage.getItem('hotkeyCapture') || '1';
  const sk = localStorage.getItem('hotkeySend') || '2';
  const tk = localStorage.getItem('hotkeyToggle') || '3';
  if (key.includes(ck)) captureScreen();
  else if (key.includes(sk)) submitQuestion();
  else if (key.includes(tk)) toggleWindow();
});

// Send saved hotkeys to Rust on startup
if (isTauri && (savedCapture !== '1' || savedSend !== '2' || savedToggle !== '3')) {
  invoke('update_hotkeys', { capture: savedCapture, send: savedSend, toggle: savedToggle }).catch(() => {});
}

// ============= Feature: Tray Icon Status =============

async function setTrayStatus(status) {
  if (isTauri) {
    try {
      await invoke('set_tray_status', { status });
    } catch {}
  }
}

// ============= Feature: Area Selection =============

async function captureArea() {
  try {
    await setTrayStatus('captured');
    const imageData = await invoke('capture_area');
    if (imageData) {
      state.capturedImage = imageData;
      if (typeof analytics !== 'undefined') analytics.increment('screenshots');
      addMessage('user', '[Area selected — press Ctrl+Alt+' + (localStorage.getItem('hotkeySend') || '2') + ' to send]');
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
    if (err !== 'Selection cancelled' && err !== 'No selection made') {
      addMessage('assistant', `Area capture failed: ${err}`);
    }
  }
  await setTrayStatus('idle');
}

document.getElementById('areaSelectBtn').addEventListener('click', captureArea);

// ============= Feature: Desktop Audio =============

async function startDesktopAudio() {
  try {
    // getDisplayMedia can capture system audio in some Chromium-based contexts
    const stream = await navigator.mediaDevices.getDisplayMedia({ audio: true, video: false });
    const audioTrack = stream.getAudioTracks()[0];
    if (!audioTrack) {
      addMessage('assistant', 'No audio track available. Desktop audio capture may not be supported in this WebView.');
      return;
    }

    // Create a MediaRecorder to capture audio
    const mediaRecorder = new MediaRecorder(stream, { mimeType: 'audio/webm' });
    const chunks = [];

    mediaRecorder.ondataavailable = (e) => {
      if (e.data.size > 0) chunks.push(e.data);
    };

    mediaRecorder.onstop = () => {
      stream.getTracks().forEach(t => t.stop());
      // Could process chunks here for speech-to-text
      addMessage('assistant', 'Desktop audio recording stopped. Transcription not yet available for system audio.');
    };

    mediaRecorder.start();
    addMessage('assistant', 'Desktop audio capture started. Note: this may not work in all WebViews.');

    // Auto-stop after 30 seconds
    setTimeout(() => {
      if (mediaRecorder.state === 'recording') mediaRecorder.stop();
    }, 30000);
  } catch (err) {
    addMessage('assistant', 'Desktop audio capture is not available in this WebView. Use microphone input instead.');
  }
}

// ============= Feature: Window Title Detection / LMS Auto-detect =============

const autoDetectLmsToggle = document.getElementById('autoDetectLmsToggle');
autoDetectLmsToggle.checked = localStorage.getItem('autoDetectLms') === 'true';

autoDetectLmsToggle.addEventListener('change', () => {
  localStorage.setItem('autoDetectLms', autoDetectLmsToggle.checked);
  if (autoDetectLmsToggle.checked) {
    startLmsPolling();
  } else {
    stopLmsPolling();
  }
});

const lmsPatterns = [
  { pattern: /canvas|instructure/i, label: 'Canvas LMS' },
  { pattern: /google\s*forms/i, label: 'Google Forms' },
  { pattern: /quizizz/i, label: 'Quizizz' },
  { pattern: /kahoot/i, label: 'Kahoot' },
  { pattern: /blackboard/i, label: 'Blackboard' },
  { pattern: /moodle/i, label: 'Moodle' },
  { pattern: /schoology/i, label: 'Schoology' },
];

let lmsPollingInterval = null;
let lastDetectedLms = '';

async function pollActiveWindow() {
  if (!isTauri) return;
  try {
    const title = await invoke('get_active_window_title');
    if (!title) return;

    for (const lms of lmsPatterns) {
      if (lms.pattern.test(title)) {
        if (lastDetectedLms !== lms.label) {
          lastDetectedLms = lms.label;
          // Show a subtle notification in the answer overlay
          document.getElementById('answerShort').textContent = `Detected: ${lms.label}`;
          document.getElementById('answerOverlay').style.display = 'flex';
          document.getElementById('answerOverlay').style.background = 'var(--accent)';
          setTimeout(() => {
            document.getElementById('answerOverlay').style.display = 'none';
            document.getElementById('answerOverlay').style.background = 'var(--green)';
          }, 3000);
        }
        return;
      }
    }
    // No LMS detected — reset
    lastDetectedLms = '';
  } catch {}
}

function startLmsPolling() {
  if (lmsPollingInterval) return;
  lmsPollingInterval = setInterval(pollActiveWindow, 5000);
}

function stopLmsPolling() {
  if (lmsPollingInterval) {
    clearInterval(lmsPollingInterval);
    lmsPollingInterval = null;
  }
  lastDetectedLms = '';
}

// Start polling if enabled on load
if (autoDetectLmsToggle.checked) {
  startLmsPolling();
}

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
