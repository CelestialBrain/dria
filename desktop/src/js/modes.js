// Study modes + per-mode chat + knowledge base (RAG)

const modesManager = {
  modes: JSON.parse(localStorage.getItem('modes') || '[]'),
  activeId: localStorage.getItem('activeMode') || 'general',

  init() {
    if (!this.modes.length) {
      this.modes = [
        { id: 'general', name: 'General', icon: '📚', files: [], keywords: [], systemPrompt: '' }
      ];
      this.save();
    }
  },

  get active() {
    return this.modes.find(m => m.id === this.activeId) || this.modes[0];
  },

  switch(id) {
    // Save current chat before switching
    this.saveChat(this.activeId, state.messages);
    this.activeId = id;
    localStorage.setItem('activeMode', id);
    // Load new mode's chat
    state.messages = this.loadChat(id);
    renderChat();
    updateModeUI();
  },

  create(name, icon = '📖', keywords = []) {
    const mode = {
      id: 'mode_' + Date.now(),
      name,
      icon,
      files: [],
      chunks: [],
      keywords,
      systemPrompt: '',
    };
    this.modes.push(mode);
    this.save();
    updateModeUI();
    return mode;
  },

  delete(id) {
    if (id === 'general') return;
    this.modes = this.modes.filter(m => m.id !== id);
    localStorage.removeItem('chat_' + id);
    localStorage.removeItem('chunks_' + id);
    if (this.activeId === id) this.switch('general');
    this.save();
    updateModeUI();
  },

  save() {
    localStorage.setItem('modes', JSON.stringify(this.modes));
  },

  // Per-mode chat persistence
  saveChat(modeId, messages) {
    const toSave = messages.slice(-50);
    localStorage.setItem('chat_' + modeId, JSON.stringify(toSave));
  },

  loadChat(modeId) {
    try {
      return JSON.parse(localStorage.getItem('chat_' + modeId) || '[]');
    } catch { return []; }
  },

  // Knowledge base — simple text chunking
  addFileText(modeId, fileName, text) {
    const mode = this.modes.find(m => m.id === modeId);
    if (!mode) return;

    // Chunk text into ~2000 char pieces with 200 char overlap
    const chunks = [];
    const chunkSize = 2000;
    const overlap = 200;
    for (let i = 0; i < text.length; i += chunkSize - overlap) {
      chunks.push({
        source: fileName,
        content: text.slice(i, i + chunkSize),
      });
    }

    mode.files.push({ name: fileName, chunkCount: chunks.length, addedAt: Date.now() });

    // Store chunks separately (can be large)
    const existing = JSON.parse(localStorage.getItem('chunks_' + modeId) || '[]');
    existing.push(...chunks);
    localStorage.setItem('chunks_' + modeId, JSON.stringify(existing));

    this.save();
    return chunks.length;
  },

  // RAG: find relevant chunks for a query
  buildContext(modeId, query) {
    const chunks = JSON.parse(localStorage.getItem('chunks_' + modeId) || '[]');
    if (!chunks.length) return '';

    const queryWords = query.toLowerCase().split(/\s+/).filter(w => w.length > 3);
    if (!queryWords.length) return chunks.slice(0, 3).map(c => c.content).join('\n\n');

    // Score chunks by keyword overlap
    const scored = chunks.map(chunk => {
      const lower = chunk.content.toLowerCase();
      const score = queryWords.reduce((s, w) => s + (lower.includes(w) ? 1 : 0), 0);
      return { ...chunk, score };
    });

    scored.sort((a, b) => b.score - a.score);
    const top = scored.slice(0, 5);
    const context = top.map(c => `[Source: ${c.source}]\n${c.content}`).join('\n\n---\n\n');

    // Cap at 3000 chars
    return context.length > 3000 ? context.slice(0, 3000) : context;
  },

  removeFile(modeId, fileName) {
    const mode = this.modes.find(m => m.id === modeId);
    if (!mode) return;
    mode.files = mode.files.filter(f => f.name !== fileName);

    const chunks = JSON.parse(localStorage.getItem('chunks_' + modeId) || '[]');
    const filtered = chunks.filter(c => c.source !== fileName);
    localStorage.setItem('chunks_' + modeId, JSON.stringify(filtered));

    this.save();
  }
};

function updateModeUI() {
  const picker = document.getElementById('modePicker');
  picker.innerHTML = '';
  modesManager.modes.forEach(m => {
    const opt = document.createElement('option');
    opt.value = m.id;
    opt.textContent = `${m.icon} ${m.name}`;
    opt.selected = m.id === modesManager.activeId;
    picker.appendChild(opt);
  });
  document.getElementById('fileCount').textContent = `${modesManager.active.files.length} files`;
}
