// Practice mode, flashcards, export

const tools = {
  // Generate practice question from knowledge base
  async generatePractice() {
    const context = modesManager.buildContext(modesManager.activeId, 'practice question exam');
    const prompt = 'Generate ONE practice exam question based on the study materials. Vary the type (MC, T/F, essay, identification). Give ONLY the question, not the answer.';
    addMessage('user', 'Generate a practice question');
    state.isStreaming = true;
    const response = await callAI(prompt + '\n\nContext:\n' + context);
    state.isStreaming = false;
    addMessage('assistant', response);
  },

  // Generate flashcards
  async generateFlashcards(count = 10) {
    const context = modesManager.buildContext(modesManager.activeId, 'flashcards key concepts');
    const prompt = `Generate ${count} flashcards. Format each as:\nQ: [question]\nA: [answer]\n\nOne blank line between cards.`;

    const response = await callAI(prompt + '\n\nContext:\n' + context);
    const cards = [];
    const lines = response.split('\n');
    let currentQ = '';
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith('Q:') || trimmed.startsWith('q:')) {
        currentQ = trimmed.slice(2).trim();
      } else if ((trimmed.startsWith('A:') || trimmed.startsWith('a:')) && currentQ) {
        cards.push({ front: currentQ, back: trimmed.slice(2).trim() });
        currentQ = '';
      }
    }
    return cards;
  },

  // Export chat to text file
  exportChat() {
    const mode = modesManager.active;
    let text = `dria Chat Export — ${mode.name}\n${'='.repeat(40)}\n\n`;
    for (const msg of state.messages) {
      const role = msg.role === 'user' ? 'You' : 'dria';
      text += `${role}:\n${msg.content}\n\n`;
    }

    const blob = new Blob([text], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `dria-chat-${mode.name}.txt`;
    a.click();
    URL.revokeObjectURL(url);
  },

  // Read text from common file types
  async readFileAsText(file) {
    const ext = file.name.split('.').pop().toLowerCase();

    if (['txt', 'md', 'html', 'htm', 'rtf', 'csv'].includes(ext)) {
      return await file.text();
    }

    if (ext === 'pdf') {
      // Use pdf.js if available, otherwise return filename
      if (window.pdfjsLib) {
        const buffer = await file.arrayBuffer();
        const pdf = await pdfjsLib.getDocument({ data: buffer }).promise;
        let text = '';
        for (let i = 1; i <= pdf.numPages; i++) {
          const page = await pdf.getPage(i);
          const content = await page.getTextContent();
          text += content.items.map(item => item.str).join(' ') + '\n';
        }
        return text;
      }
      return `[PDF file: ${file.name} — install pdf.js for text extraction]`;
    }

    // For other types, try as text
    try { return await file.text(); } catch { return ''; }
  }
};
