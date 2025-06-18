import SwiftUI
import WebKit
import Network

class LocalHTTPServer: NSObject {
    private var listener: NWListener?
    private let port: UInt16
    private let documentRoot: String
    
    init(port: UInt16 = 8080, documentRoot: String) {
        self.port = port
        self.documentRoot = documentRoot
        super.init()
    }
    
    func start() {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: .global())
            print("Local server started on port \(port)")
        } catch {
            print("Failed to start server: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        
        func receiveRequest() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
                guard let data = data, let request = String(data: data, encoding: .utf8) else {
                    connection.cancel()
                    return
                }
                
                self?.processRequest(request, connection: connection)
                
                if isComplete {
                    connection.cancel()
                }
            }
        }
        
        receiveRequest()
    }
    
    private func processRequest(_ request: String, connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else { return }
        
        var path = components[1]
        if path == "/" {
            path = "/index.html"
        }
        
        let filePath = documentRoot + path
        
        var response: String
        var contentType = "text/html"
        
        if FileManager.default.fileExists(atPath: filePath) {
            do {
                if path.hasSuffix(".js") {
                    contentType = "application/javascript"
                } else if path.hasSuffix(".css") {
                    contentType = "text/css"
                } else if path.hasSuffix(".png") {
                    contentType = "image/png"
                } else if path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") {
                    contentType = "image/jpeg"
                } else if path.hasSuffix(".gif") {
                    contentType = "image/gif"
                } else if path.hasSuffix(".svg") {
                    contentType = "image/svg+xml"
                } else if path.hasSuffix(".json") {
                    contentType = "application/json"
                } else if path.hasSuffix(".woff") || path.hasSuffix(".woff2") {
                    contentType = "font/woff2"
                } else if path.hasSuffix(".ttf") {
                    contentType = "font/ttf"
                } else if path.hasSuffix(".otf") {
                    contentType = "font/otf"
                } else if path.hasSuffix(".mp3") {
                    contentType = "audio/mpeg"
                } else if path.hasSuffix(".wav") {
                    contentType = "audio/wav"
                } else if path.hasSuffix(".ogg") {
                    contentType = "audio/ogg"
                } else if path.hasSuffix(".webp") {
                    contentType = "image/webp"
                }
                
                if contentType.hasPrefix("image/") || contentType.hasPrefix("font/") || contentType.hasPrefix("audio/") {
                    let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
                    response = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(data.count)\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
                    
                    let responseData = response.data(using: .utf8)! + data
                    connection.send(content: responseData, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    return
                } else {
                    let content = try String(contentsOfFile: filePath, encoding: .utf8)
                    response = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(content.utf8.count)\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n\(content)"
                }
            } catch {
                response = "HTTP/1.1 500 Internal Server Error\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nError reading file: \(error)"
            }
        } else {
            response = "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nFile not found: \(path)"
        }
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

struct WebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // JavaScript configuration
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // Media configuration
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = false
        config.mediaTypesRequiringUserActionForPlayback = []
        
        // Create the web view
        let webView = WKWebView(frame: .zero, configuration: config)
        
        // Set up delegates
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // Enable debugging
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
        
        // CRITICAL: Fix scroll view settings to prevent zooming issues
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = false  // Disable scrolling to prevent layout issues
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        
        // CRITICAL: Disable all zooming
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.zoomScale = 1.0
        webView.scrollView.isUserInteractionEnabled = true
        webView.scrollView.delaysContentTouches = false
        webView.scrollView.canCancelContentTouches = true
        
        // Disable navigation gestures that can cause constraint issues
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        
        // Set explicit content mode
        webView.contentMode = .scaleAspectFit
        
        // Fix autoresizing constraints
        webView.translatesAutoresizingMaskIntoConstraints = false
        
        // Start server and load content
        context.coordinator.startServerAndLoad(webView: webView)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Ensure consistent scroll view settings on updates
        uiView.scrollView.minimumZoomScale = 1.0
        uiView.scrollView.maximumZoomScale = 1.0
        uiView.scrollView.zoomScale = 1.0
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private var server: LocalHTTPServer?
        
        func startServerAndLoad(webView: WKWebView) {
            guard let distPath = Bundle.main.path(forResource: "dist", ofType: nil) else {
                print("Could not find dist folder")
                loadErrorPage(webView: webView)
                return
            }
            
            server = LocalHTTPServer(port: 8080, documentRoot: distPath)
            server?.start()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let url = URL(string: "http://localhost:8080")!
                print("Loading from local server: \(url)")
                webView.load(URLRequest(url: url))
            }
        }
        
        private func loadErrorPage(webView: WKWebView) {
            let errorHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
                <style>
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                        background: #1a1a1a;
                        color: #ffffff;
                        text-align: center;
                        padding: 20px;
                        margin: 0;
                        font-size: 14px;
                    }
                    h1 { color: #ff6b6b; font-size: 24px; }
                    p { color: #cccccc; margin: 10px 0; }
                </style>
            </head>
            <body>
                <h1>Local Server Error</h1>
                <p>Could not start local HTTP server or find game files.</p>
            </body>
            </html>
            """
            webView.loadHTMLString(errorHTML, baseURL: nil)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("Page loaded successfully")
            
            // Comprehensive fix script
            let comprehensiveFixScript = """
            console.log('Applying comprehensive fixes...');
            
            // 1. VIEWPORT FIX - Critical for proper scaling
            function fixViewport() {
                // Remove existing viewport tags
                const existingViewports = document.querySelectorAll('meta[name="viewport"]');
                existingViewports.forEach(v => v.remove());
                
                // Add proper viewport
                const viewport = document.createElement('meta');
                viewport.name = 'viewport';
                viewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';
                document.head.appendChild(viewport);
                console.log('Viewport fixed');
            }
            
            // 2. ZOOM PREVENTION
            function preventZoom() {
                // Prevent zoom on double tap
                let lastTouchEnd = 0;
                document.addEventListener('touchend', function(event) {
                    const now = (new Date()).getTime();
                    if (now - lastTouchEnd <= 300) {
                        if (!event.target.matches('input, textarea, select, button')) {
                            event.preventDefault();
                        }
                    }
                    lastTouchEnd = now;
                }, { passive: false });
                
                // Prevent pinch zoom
                document.addEventListener('gesturestart', function(e) {
                    e.preventDefault();
                }, { passive: false });
                
                document.addEventListener('gesturechange', function(e) {
                    e.preventDefault();
                }, { passive: false });
                
                document.addEventListener('gestureend', function(e) {
                    e.preventDefault();
                }, { passive: false });
                
                console.log('Zoom prevention applied');
            }
            
            // 3. LAYOUT FIXES
            function fixLayout() {
                const layoutStyles = document.createElement('style');
                layoutStyles.id = 'ios-layout-fixes';
                layoutStyles.innerHTML = `
                    /* Base layout fixes */
                    html, body {
                        margin: 0;
                        padding: 0;
                        overflow-x: hidden;
                        width: 100vw;
                        height: 100vh;
                        position: fixed;
                        top: 0;
                        left: 0;
                        -webkit-overflow-scrolling: touch;
                        -webkit-user-select: none;
                        user-select: none;
                    }
                    
                    /* Game container */
                    #app, .game-container, canvas {
                        width: 100vw !important;
                        height: 100vh !important;
                        max-width: 100vw !important;
                        max-height: 100vh !important;
                        object-fit: contain !important;
                        display: block !important;
                        margin: 0 !important;
                        padding: 0 !important;
                        border: none !important;
                        outline: none !important;
                    }
                    
                    /* Prevent scrolling on game area */
                    canvas, .game-canvas {
                        touch-action: none !important;
                        -webkit-touch-callout: none !important;
                        -webkit-user-select: none !important;
                        user-select: none !important;
                    }
                `;
                
                // Remove existing styles
                const existing = document.getElementById('ios-layout-fixes');
                if (existing) existing.remove();
                
                document.head.appendChild(layoutStyles);
                console.log('Layout fixes applied');
            }
            
            // 4. INPUT FIELD FIXES
            function fixInputs() {
                const inputStyles = document.createElement('style');
                inputStyles.id = 'ios-input-fixes';
                inputStyles.innerHTML = `
                    /* Input field fixes */
                    input, textarea, select {
                        -webkit-appearance: none !important;
                        appearance: none !important;
                        background: #2a2a2a !important;
                        color: #ffffff !important;
                        border: 2px solid #444 !important;
                        border-radius: 6px !important;
                        padding: 8px 12px !important;
                        font-size: 16px !important;
                        font-family: -apple-system, BlinkMacSystemFont, sans-serif !important;
                        width: auto !important;
                        max-width: 280px !important;
                        box-sizing: border-box !important;
                        -webkit-user-select: text !important;
                        user-select: text !important;
                        touch-action: manipulation !important;
                        z-index: 10000 !important;
                        position: relative !important;
                    }
                    
                    input:focus, textarea:focus, select:focus {
                        outline: none !important;
                        border-color: #007AFF !important;
                        background: #333 !important;
                        -webkit-user-select: text !important;
                        user-select: text !important;
                    }
                    
                    input::placeholder, textarea::placeholder {
                        color: #888 !important;
                        opacity: 1 !important;
                    }
                    
                    /* Button fixes */
                    button, input[type="submit"], input[type="button"] {
                        -webkit-appearance: none !important;
                        appearance: none !important;
                        background: #007AFF !important;
                        color: white !important;
                        border: none !important;
                        border-radius: 6px !important;
                        padding: 10px 20px !important;
                        font-size: 16px !important;
                        font-family: -apple-system, BlinkMacSystemFont, sans-serif !important;
                        cursor: pointer !important;
                        touch-action: manipulation !important;
                        -webkit-user-select: none !important;
                        user-select: none !important;
                    }
                    
                    button:active, input[type="submit"]:active, input[type="button"]:active {
                        background: #0051D0 !important;
                        transform: scale(0.98) !important;
                    }
                    
                    /* Form container styling */
                    form, .form-container, .login-form, .auth-form {
                        background: rgba(0, 0, 0, 0.9) !important;
                        border: 1px solid #444 !important;
                        border-radius: 8px !important;
                        padding: 20px !important;
                        margin: 20px auto !important;
                        max-width: 320px !important;
                        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.5) !important;
                    }
                    
                    /* Remove white box backgrounds */
                    .input-container, .form-group, .field-wrapper {
                        background: transparent !important;
                        border: none !important;
                        padding: 0 !important;
                        margin: 5px 0 !important;
                    }
                `;
                
                // Remove existing input styles
                const existing = document.getElementById('ios-input-fixes');
                if (existing) existing.remove();
                
                document.head.appendChild(inputStyles);
                
                // Apply direct fixes to existing inputs
                const allInputs = document.querySelectorAll('input, textarea, select');
                console.log('Found', allInputs.length, 'input elements');
                
                allInputs.forEach((input, index) => {
                    console.log('Fixing input', index, input.type || input.tagName);
                    
                    // Force styles
                    input.style.cssText = `
                        background: #2a2a2a !important;
                        color: #ffffff !important;
                        border: 2px solid #444 !important;
                        border-radius: 6px !important;
                        padding: 8px 12px !important;
                        font-size: 16px !important;
                        width: auto !important;
                        max-width: 280px !important;
                        -webkit-appearance: none !important;
                        -webkit-user-select: text !important;
                        user-select: text !important;
                        touch-action: manipulation !important;
                        z-index: 10000 !important;
                        position: relative !important;
                    `;
                    
                    // Add enhanced event handlers
                    input.addEventListener('touchstart', function(e) {
                        e.stopPropagation();
                        this.style.borderColor = '#007AFF';
                    }, { passive: true });
                    
                    input.addEventListener('focus', function(e) {
                        console.log('Input focused:', this);
                        this.style.borderColor = '#007AFF';
                        this.style.background = '#333';
                        this.style.webkitUserSelect = 'text';
                        this.style.userSelect = 'text';
                    });
                    
                    input.addEventListener('blur', function(e) {
                        this.style.borderColor = '#444';
                        this.style.background = '#2a2a2a';
                    });
                    
                    input.addEventListener('click', function(e) {
                        e.stopPropagation();
                        setTimeout(() => {
                            this.focus();
                            if (this.select && this.type !== 'button' && this.type !== 'submit') {
                                this.select();
                            }
                        }, 50);
                    });
                });
                
                console.log('Input fixes applied to', allInputs.length, 'elements');
            }
            
            // 5. CONTAINER FIXES
            function fixContainers() {
                // Remove white box backgrounds from common container classes
                const containers = document.querySelectorAll('.input-container, .form-group, .field-wrapper, .white-box, .input-box');
                containers.forEach(container => {
                    container.style.background = 'transparent';
                    container.style.backgroundColor = 'transparent';
                    container.style.border = 'none';
                    container.style.boxShadow = 'none';
                });
                
                console.log('Fixed', containers.length, 'container backgrounds');
            }
            
            // Apply all fixes
            fixViewport();
            preventZoom();
            fixLayout();
            fixInputs();
            fixContainers();
            
            // Watch for new elements
            const observer = new MutationObserver((mutations) => {
                let shouldRefix = false;
                mutations.forEach((mutation) => {
                    if (mutation.type === 'childList') {
                        mutation.addedNodes.forEach((node) => {
                            if (node.nodeType === 1) { // Element node
                                if (node.matches && (node.matches('input, textarea, select') || 
                                    node.querySelector && node.querySelector('input, textarea, select'))) {
                                    shouldRefix = true;
                                }
                            }
                        });
                    }
                });
                
                if (shouldRefix) {
                    console.log('New inputs detected, reapplying fixes...');
                    setTimeout(() => {
                        fixInputs();
                        fixContainers();
                    }, 100);
                }
            });
            
            observer.observe(document.body, {
                childList: true,
                subtree: true
            });
            
            // Reapply fixes periodically
            setTimeout(() => {
                fixInputs();
                fixContainers();
            }, 2000);
            
            setTimeout(() => {
                fixInputs();
                fixContainers();
            }, 5000);
            
            console.log('All fixes applied successfully');
            """
            
            webView.evaluateJavaScript(comprehensiveFixScript) { result, error in
                if let error = error {
                    print("Fix script error: \(error)")
                } else {
                    print("Comprehensive fixes applied successfully")
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Navigation failed: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
        
        // Handle JavaScript alerts, confirms, and prompts
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: "Alert", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler()
            })
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(alert, animated: true)
            } else {
                completionHandler()
            }
        }
        
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: "Confirm", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(true)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                completionHandler(false)
            })
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(alert, animated: true)
            } else {
                completionHandler(false)
            }
        }
        
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: "Input", message: prompt, preferredStyle: .alert)
            alert.addTextField { textField in
                textField.text = defaultText
                textField.placeholder = "Enter text"
            }
            
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                completionHandler(nil)
            })
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(alert, animated: true)
            } else {
                completionHandler(nil)
            }
        }
        
        deinit {
            server?.stop()
        }
    }
}
