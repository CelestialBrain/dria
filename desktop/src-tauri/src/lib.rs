use tauri::{
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Emitter, Manager,
};
use base64::Engine;
use tauri_plugin_autostart::MacosLauncher;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

#[tauri::command]
fn capture_screen() -> Result<String, String> {
    let screens = screenshots::Screen::all().map_err(|e| format!("{:?}", e))?;
    let screen = screens.first().ok_or("No screen found".to_string())?;
    let image = screen.capture().map_err(|e| format!("{:?}", e))?;
    // Encode as PNG via the image crate
    let mut png_bytes: Vec<u8> = Vec::new();
    let (w, h) = image.dimensions();
    let encoder = image::codecs::png::PngEncoder::new(&mut png_bytes);
    image::ImageEncoder::write_image(
        encoder,
        image.as_raw(),
        w, h,
        image::ExtendedColorType::Rgba8,
    ).map_err(|e| e.to_string())?;
    let b64 = base64::engine::general_purpose::STANDARD.encode(&png_bytes);
    Ok(format!("data:image/png;base64,{}", b64))
}

#[tauri::command]
fn get_clipboard_text() -> Result<String, String> {
    let mut clipboard = arboard::Clipboard::new().map_err(|e| e.to_string())?;
    clipboard.get_text().map_err(|e| e.to_string())
}

#[tauri::command]
fn set_clipboard_text(text: String) -> Result<(), String> {
    let mut clipboard = arboard::Clipboard::new().map_err(|e| e.to_string())?;
    clipboard.set_text(text).map_err(|e| e.to_string())
}

#[tauri::command]
fn read_file_text(path: String) -> Result<String, String> {
    std::fs::read_to_string(&path).map_err(|e| format!("Failed to read {}: {}", path, e))
}

// Lock popover — global atomic flag
static POPOVER_LOCKED: AtomicBool = AtomicBool::new(false);

#[tauri::command]
fn set_lock_popover(locked: bool) {
    POPOVER_LOCKED.store(locked, Ordering::Relaxed);
}

#[tauri::command]
fn get_autostart(app_handle: tauri::AppHandle) -> Result<bool, String> {
    use tauri_plugin_autostart::ManagerExt;
    app_handle
        .autolaunch()
        .is_enabled()
        .map_err(|e| e.to_string())
}

#[tauri::command]
fn set_autostart(app_handle: tauri::AppHandle, enabled: bool) -> Result<(), String> {
    use tauri_plugin_autostart::ManagerExt;
    let autostart = app_handle.autolaunch();
    if enabled {
        autostart.enable().map_err(|e| e.to_string())
    } else {
        autostart.disable().map_err(|e| e.to_string())
    }
}

// ============= Feature 1: Configurable Hotkeys =============

// Store current hotkey bindings
static HOTKEY_CAPTURE: Mutex<Option<String>> = Mutex::new(None);
static HOTKEY_SEND: Mutex<Option<String>> = Mutex::new(None);
static HOTKEY_TOGGLE: Mutex<Option<String>> = Mutex::new(None);

#[tauri::command]
fn update_hotkeys(
    app_handle: tauri::AppHandle,
    capture: String,
    send: String,
    toggle: String,
) -> Result<(), String> {
    use tauri_plugin_global_shortcut::GlobalShortcutExt;

    // Unregister all existing shortcuts
    let _ = app_handle.global_shortcut().unregister_all();

    // Helper to register a shortcut and emit event
    let register = |key: &str, label: &str| -> Result<(), String> {
        let shortcut_str = format!("Ctrl+Alt+{}", key);
        let lbl = label.to_string();
        let handle = app_handle.clone();
        app_handle
            .global_shortcut()
            .on_shortcut(
                shortcut_str.as_str(),
                move |_app, _shortcut, event| {
                    if let tauri_plugin_global_shortcut::ShortcutState::Pressed = event.state {
                        let _ = handle.emit("global-shortcut", &lbl);
                    }
                },
            )
            .map_err(|e| e.to_string())?;
        Ok(())
    };

    register(&capture, &format!("Ctrl+Alt+{}", capture))?;
    register(&send, &format!("Ctrl+Alt+{}", send))?;
    register(&toggle, &format!("Ctrl+Alt+{}", toggle))?;

    // Store current values
    *HOTKEY_CAPTURE.lock().unwrap() = Some(capture);
    *HOTKEY_SEND.lock().unwrap() = Some(send);
    *HOTKEY_TOGGLE.lock().unwrap() = Some(toggle);

    Ok(())
}

// ============= Feature 2: Tray Icon Status =============

#[tauri::command]
fn set_tray_status(app_handle: tauri::AppHandle, status: String) -> Result<(), String> {
    let tooltip = match status.as_str() {
        "idle" => "dria — Idle",
        "captured" => "dria — Screenshot Captured",
        "processing" => "dria — Processing...",
        "ready" => "dria — Answer Ready",
        "recording" => "dria — Recording Voice...",
        "error" => "dria — Error",
        _ => "dria — AI Study Assistant",
    };

    if let Some(tray) = app_handle.tray_by_id("main-tray") {
        let _ = tray.set_tooltip(Some(tooltip));
    }

    Ok(())
}

// ============= Feature 3: Area Selection =============

#[tauri::command]
fn capture_area() -> Result<String, String> {
    let temp = std::env::temp_dir().join(format!(
        "dria_area_{}.png",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis()
    ));
    let path = temp.to_str().unwrap();

    #[cfg(target_os = "macos")]
    {
        let status = std::process::Command::new("/usr/sbin/screencapture")
            .args(["-i", "-x", path])
            .status()
            .map_err(|e| e.to_string())?;
        if !status.success() {
            return Err("Selection cancelled".into());
        }
    }

    #[cfg(target_os = "windows")]
    {
        let _status = std::process::Command::new("powershell")
            .args([
                "-Command",
                &format!(
                    "Add-Type -AssemblyName System.Windows.Forms; \
                     [System.Windows.Forms.Screen]::PrimaryScreen | Out-Null; \
                     Start-Process snippingtool /clip; Start-Sleep 5"
                ),
            ])
            .status()
            .map_err(|e| e.to_string())?;
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        return Err("Area selection not supported on this platform".into());
    }

    if temp.exists() {
        let data = std::fs::read(&temp).map_err(|e| e.to_string())?;
        let _ = std::fs::remove_file(&temp);
        let b64 = base64::engine::general_purpose::STANDARD.encode(&data);
        Ok(format!("data:image/png;base64,{}", b64))
    } else {
        Err("No selection made".into())
    }
}

// ============= Feature 5: Window Title Detection =============

#[tauri::command]
fn get_active_window_title() -> Result<String, String> {
    #[cfg(target_os = "macos")]
    {
        let output = std::process::Command::new("osascript")
            .args([
                "-e",
                "tell application \"System Events\" to get name of first window of \
                 (first application process whose frontmost is true)",
            ])
            .output()
            .map_err(|e| e.to_string())?;
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    }

    #[cfg(target_os = "windows")]
    {
        let output = std::process::Command::new("powershell")
            .args([
                "-Command",
                "(Get-Process | Where-Object {$_.MainWindowTitle -ne ''} | \
                 Sort-Object -Property CPU -Descending | Select-Object -First 1).MainWindowTitle",
            ])
            .output()
            .map_err(|e| e.to_string())?;
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        Ok(String::new())
    }
}

// ============= Feature: Toggle Window =============

#[tauri::command]
fn toggle_window(app_handle: tauri::AppHandle) -> Result<(), String> {
    if let Some(window) = app_handle.get_webview_window("main") {
        if window.is_visible().unwrap_or(false) {
            window.hide().map_err(|e| e.to_string())?;
        } else {
            window.show().map_err(|e| e.to_string())?;
            window.set_focus().map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_autostart::init(MacosLauncher::LaunchAgent, Some(vec!["--flag1"])))
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }

            // System tray — click to toggle window
            let _tray = TrayIconBuilder::with_id("main-tray")
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip("dria — AI Study Assistant")
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event {
                        // Respect lock popover setting
                        if POPOVER_LOCKED.load(Ordering::Relaxed) {
                            return;
                        }
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            if window.is_visible().unwrap_or(false) {
                                let _ = window.hide();
                            } else {
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                    }
                })
                .build(app)?;

            // Register default global shortcuts (Ctrl+Alt+1/2/3)
            {
                use tauri_plugin_global_shortcut::GlobalShortcutExt;
                let handle = app.handle().clone();

                let combos = ["Ctrl+Alt+1", "Ctrl+Alt+2", "Ctrl+Alt+3"];
                for combo in &combos {
                    let label = combo.to_string();
                    let h = handle.clone();
                    let _ = app.handle().global_shortcut().on_shortcut(
                        *combo,
                        move |_app, _shortcut, event| {
                            if let tauri_plugin_global_shortcut::ShortcutState::Pressed = event.state {
                                let _ = h.emit("global-shortcut", &label);
                            }
                        },
                    );
                }
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            capture_screen,
            get_clipboard_text,
            set_clipboard_text,
            read_file_text,
            set_lock_popover,
            get_autostart,
            set_autostart,
            update_hotkeys,
            set_tray_status,
            capture_area,
            get_active_window_title,
            toggle_window,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
