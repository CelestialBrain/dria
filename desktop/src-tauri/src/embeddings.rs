//! Local sentence embeddings for the Windows/Linux Tauri port.
//!
//! Mirrors the shape of `LocalEmbedder` in the macOS Swift code so the JS
//! frontend can call either platform with the same protocol.
//!
//! Enabled with the `embeddings` cargo feature (off by default to keep
//! base builds fast — fastembed pulls in ONNX runtime and downloads a
//! ~22 MB model on first run).
//!
//! Fallback: when this module is disabled or model init fails, the JS
//! side should fall back to keyword TF-IDF (same as the macOS path when
//! `LocalEmbedder.make` returns nil).

#![cfg(feature = "embeddings")]

use fastembed::{EmbeddingModel, InitOptions, TextEmbedding};
use sha2::{Digest, Sha256};
use std::sync::{Mutex, OnceLock};

static EMBEDDER: OnceLock<Mutex<Option<TextEmbedding>>> = OnceLock::new();

fn embedder() -> &'static Mutex<Option<TextEmbedding>> {
    EMBEDDER.get_or_init(|| Mutex::new(None))
}

fn ensure_loaded() -> Result<(), String> {
    let cell = embedder();
    let mut guard = cell.lock().map_err(|e| e.to_string())?;
    if guard.is_some() {
        return Ok(());
    }
    let model = TextEmbedding::try_new(
        InitOptions::new(EmbeddingModel::AllMiniLML6V2).with_show_download_progress(false),
    )
    .map_err(|e| format!("embedder init: {e}"))?;
    *guard = Some(model);
    Ok(())
}

#[tauri::command]
pub fn embed_texts(texts: Vec<String>) -> Result<Vec<Vec<f32>>, String> {
    ensure_loaded()?;
    let cell = embedder();
    let guard = cell.lock().map_err(|e| e.to_string())?;
    let model = guard.as_ref().ok_or("embedder not loaded")?;
    model
        .embed(texts, None)
        .map_err(|e| format!("embed failed: {e}"))
}

#[tauri::command]
pub fn embed_query(text: String) -> Result<Vec<f32>, String> {
    let mut v = embed_texts(vec![text])?;
    v.pop().ok_or("empty embedding result".into())
}

#[tauri::command]
pub fn content_hash(text: String) -> String {
    let mut hasher = Sha256::new();
    hasher.update(text.as_bytes());
    format!("{:x}", hasher.finalize())
}

#[tauri::command]
pub fn cosine_similarity(a: Vec<f32>, b: Vec<f32>) -> f32 {
    if a.len() != b.len() || a.is_empty() {
        return 0.0;
    }
    let mut dot = 0.0f32;
    let mut norm_a = 0.0f32;
    let mut norm_b = 0.0f32;
    for i in 0..a.len() {
        dot += a[i] * b[i];
        norm_a += a[i] * a[i];
        norm_b += b[i] * b[i];
    }
    let denom = norm_a.sqrt() * norm_b.sqrt();
    if denom > 0.0 { dot / denom } else { 0.0 }
}

/// Returns the on-disk cache path matching the macOS layout
/// (`<app-cache>/dria/embeddings.json`).
#[tauri::command]
pub fn embeddings_cache_path(app_handle: tauri::AppHandle) -> Result<String, String> {
    use tauri::Manager;
    let dir = app_handle
        .path()
        .app_cache_dir()
        .map_err(|e| e.to_string())?
        .join("embeddings.json");
    if let Some(parent) = dir.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    dir.to_str()
        .map(|s| s.to_string())
        .ok_or("invalid cache path".into())
}
