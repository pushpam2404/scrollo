// Renders an HTML file to a PNG with WebKit (no browser needed). Usage: render_html <file.html> <width> <height> <out.png>
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count == 5, let w = Double(args[2]), let h = Double(args[3]) else {
    print("usage: render_html <file.html> <width> <height> <out.png>"); exit(2)
}
let html = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[4])

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

final class Loader: NSObject, WKNavigationDelegate {
    var done: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done?() }
}

let cfg = WKWebViewConfiguration()
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: w, height: h), configuration: cfg)
web.setValue(false, forKey: "drawsBackground")
let loader = Loader()
web.navigationDelegate = loader
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h), styleMask: [.borderless], backing: .buffered, defer: false)
win.contentView = web
win.backgroundColor = .clear
win.orderFrontRegardless()

loader.done = {
    // Give images and fonts a moment to settle before the snapshot.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        let snap = WKSnapshotConfiguration()
        snap.rect = NSRect(x: 0, y: 0, width: w, height: h)
        web.takeSnapshot(with: snap) { image, error in
            guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                print("snapshot failed:", error?.localizedDescription ?? "?"); exit(1)
            }
            try? png.write(to: out)
            print("wrote", out.lastPathComponent, rep.pixelsWide, "x", rep.pixelsHigh)
            exit(0)
        }
    }
}
web.loadFileURL(html, allowingReadAccessTo: URL(fileURLWithPath: "/"))
app.run()
