/* dria custom functions for Excel — calls localhost bridge server */

const BRIDGE_URL = "http://127.0.0.1:7842";

function getToken() {
  // Persisted across sessions in the document settings.
  // User pastes it via the taskpane (commands.html opens it).
  return (
    (Office?.context?.document?.settings?.get("driaToken")) ||
    localStorage.getItem("driaToken") ||
    ""
  );
}

async function callBridge(path, body) {
  const token = getToken();
  if (!token) {
    throw new Error("dria not configured. Open the dria Settings task pane and paste your bridge token.");
  }
  const res = await fetch(BRIDGE_URL + path, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer " + token,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error("dria bridge error " + res.status + ": " + text);
  }
  return res.json();
}

/**
 * Ask dria a question.
 * @customfunction CHATGPT
 * @param {string} prompt
 * @param {string} [context]
 * @param {string} [mode]
 * @returns {Promise<string>}
 */
async function CHATGPT(prompt, context, mode) {
  const finalPrompt = context ? `${prompt}\n\nContext:\n${context}` : prompt;
  const out = await callBridge("/v1/ask", {
    prompt: finalPrompt,
    mode: mode || undefined,
    useKnowledgeBase: true,
  });
  return (out.answer || "").trim();
}

/**
 * Classify text into one of comma-separated categories.
 * @customfunction DRIA_CLASSIFY
 * @param {string} text
 * @param {string} categories
 * @returns {Promise<string>}
 */
async function DRIA_CLASSIFY(text, categories) {
  const list = (categories || "").split(",").map((s) => s.trim()).filter(Boolean);
  const out = await callBridge("/v1/classify", { text: text, categories: list });
  return out.label || "";
}

/**
 * Extract a value from text following an instruction.
 * @customfunction DRIA_EXTRACT
 * @param {string} text
 * @param {string} instruction
 * @returns {Promise<string>}
 */
async function DRIA_EXTRACT(text, instruction) {
  const out = await callBridge("/v1/extract", { text: text, instruction: instruction });
  return out.value || "";
}

CustomFunctions.associate("CHATGPT", CHATGPT);
CustomFunctions.associate("DRIA_CLASSIFY", DRIA_CLASSIFY);
CustomFunctions.associate("DRIA_EXTRACT", DRIA_EXTRACT);
