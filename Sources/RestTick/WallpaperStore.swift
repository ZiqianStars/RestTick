import AppKit
import CoreGraphics
import CryptoKit
import ImageIO

/// 本地护眼图：内置 5 张随 App 打包的风景照片，首次运行时复制到图库目录，
/// 之后直接从 Application Support 读取，断网也完全可用。
/// 如果用户把自定义图片放进该目录，则优先使用自定义图片。
///
/// 目录扫描、内置图生成、图片解码全部在后台队列完成，主线程只维护清单并接收解码好的图片。
/// 清单签名（文件名/大小/修改时间/目标像素）不变时不会清空缓存，避免每次休息都重新解码。
final class WallpaperStore {
    static let shared = WallpaperStore()

    private let folder: URL
    private let cache = NSCache<NSURL, NSImage>()
    private let scanQueue = DispatchQueue(label: "resttick.wallpaper.scan", qos: .utility)
    private let decodeQueue = DispatchQueue(
        label: "resttick.wallpaper.decode",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// 只在主线程读写。
    private var items: [URL] = []
    private var manifestSignature = ""
    private var scanInFlight = false
    private var pendingCompletions: [() -> Void] = []
    private var targetPixelSize: Int

    /// 图库目录：用户可把自定义背景图直接放进来。
    var folderURL: URL {
        ensureFolder()
        return folder
    }

    /// 当前可用背景图数量（自定义优先，否则为内置图）。
    var count: Int { items.count }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appendingPathComponent("RestTick/Backgrounds", isDirectory: true)
        cache.countLimit = 3
        cache.totalCostLimit = 96 * 1024 * 1024
        targetPixelSize = Self.screenPixelSize()
        ensureFolder()
        reload()
    }

    // MARK: - 清单

    /// 后台重新扫描目录。用户新增/删除图片后调用即可生效；
    /// 清单没有变化时不清缓存，下次休息可以直接复用已解码的图片。
    func reload(completion: (() -> Void)? = nil) {
        targetPixelSize = Self.screenPixelSize()
        if let completion { pendingCompletions.append(completion) }
        guard !scanInFlight else { return }
        scanInFlight = true

        let pixelSize = targetPixelSize
        scanQueue.async { [weak self] in
            guard let self else { return }
            let result = Self.scan(folder: self.folder, pixelSize: pixelSize)
            DispatchQueue.main.async {
                self.apply(result)
                self.scanInFlight = false
                let completions = self.pendingCompletions
                self.pendingCompletions.removeAll()
                for completion in completions { completion() }
            }
        }
    }

    private func apply(_ result: ScanResult) {
        if result.signature != manifestSignature {
            manifestSignature = result.signature
            cache.removeAllObjects()
            Log.wallpaper.notice("图库清单变化，已清空缓存：\(result.items.count) 张")
        }
        items = result.items
    }

    // MARK: - 取图

    /// 按索引异步取图（自动取模），已降采样并缓存；completion 固定回到主线程。
    func loadImage(at index: Int, completion: @escaping (NSImage?) -> Void) {
        guard !items.isEmpty else {
            completion(nil)
            return
        }
        let safe = ((index % items.count) + items.count) % items.count
        let url = items[safe]
        if let cached = cache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }

        let pixelSize = targetPixelSize
        decodeQueue.async { [weak self] in
            let image = Self.decode(url: url, maxPixel: pixelSize)
            if let image, let self {
                self.cache.setObject(image, forKey: url as NSURL, cost: image.approximateByteCost)
            } else {
                Log.wallpaper.error("图片解码失败：\(url.lastPathComponent, privacy: .public)")
            }
            DispatchQueue.main.async { completion(image) }
        }
    }

    /// 启动后空闲时预热：触发一次扫描并解码第一张图。
    func prewarm() {
        reload { [weak self] in
            self?.loadImage(at: 0) { _ in }
        }
    }

    // MARK: - 扫描与回退

    private struct ScanResult {
        let items: [URL]
        let signature: String
    }

    private func ensureFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private static func scan(folder: URL, pixelSize: Int) -> ScanResult {
        let allowed: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff"]
        let custom = ((try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        )) ?? [])
            .filter { allowed.contains($0.pathExtension.lowercased()) }
            .filter { !$0.lastPathComponent.hasPrefix("resttick-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var images: [URL] = []
        var records: [String] = []
        for url in custom {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let size = values.fileSize,
                  let modified = values.contentModificationDate,
                  isLoadable(url) else { continue }
            images.append(url)
            records.append("\(url.lastPathComponent):\(size):\(Int(modified.timeIntervalSince1970))")
        }

        var signature = "px=\(pixelSize)|" + records.joined(separator: ",")
        if images.isEmpty {
            let builtins = builtinItems(in: folder)
            let builtinRecords = builtins.map { url -> String in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = values?.fileSize ?? 0
                let modified = Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
                return "\(url.lastPathComponent):\(size):\(modified)"
            }
            signature += "|builtin=" + builtinRecords.joined(separator: ",")
            return ScanResult(items: builtins, signature: signature)
        }
        return ScanResult(items: images, signature: signature)
    }

    /// 只读图片元数据，快速排除损坏/伪装文件，不做完整解码。
    private static func isLoadable(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return false }
        return true
    }

    /// 内置图随 App 打包在 Resources/Backgrounds，首次运行时复制到图库目录，
    /// 之后每次扫描按内容哈希比对，内置图有更新就覆盖同名旧图。
    private static let builtinNames = [
        "resttick-01.jpg",
        "resttick-02.jpg",
        "resttick-03.jpg",
        "resttick-04.jpg",
        "resttick-05.jpg"
    ]

    private static func builtinItems(in folder: URL) -> [URL] {
        guard let bundleFolder = Bundle.main.resourceURL?
            .appendingPathComponent("Backgrounds", isDirectory: true) else { return [] }

        removeLegacyBuiltins(in: folder)

        var result: [URL] = []
        for name in builtinNames {
            let source = bundleFolder.appendingPathComponent(name)
            let destination = folder.appendingPathComponent(name)
            syncBuiltin(named: name, from: source, to: destination)
            if isLoadable(destination) { result.append(destination) }
        }
        return result
    }

    /// 用内容哈希判断运行时副本是否过期；缺失、损坏或内容变化时都重新复制。
    private static func syncBuiltin(named name: String, from source: URL, to destination: URL) {
        guard let sourceHash = contentHash(of: source) else {
            Log.wallpaper.error("读取内置图失败：\(name, privacy: .public)")
            return
        }
        if contentHash(of: destination) == sourceHash { return }

        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            Log.wallpaper.notice("已同步内置图：\(name, privacy: .public)")
        } catch {
            Log.wallpaper.error(
                "复制内置图失败 \(name, privacy: .public)：\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func contentHash(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 旧版本在应用支持目录里生成的渐变图，已被内置照片取代，顺手清理。
    private static func removeLegacyBuiltins(in folder: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in files
        where url.lastPathComponent.hasPrefix("resttick-") && url.pathExtension.lowercased() == "png" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - 解码

    /// 用 ImageIO 生成缩略图：同时完成降采样与 EXIF/HEIC 方向矫正。
    private static func decode(url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
        }
        // 极少数格式无法生成缩略图时退回原图加载。
        return NSImage(contentsOf: url)
    }

    /// 按最大屏幕的像素长边确定降采样尺寸，避免超过 4K 的无效内存占用。需在主线程调用。
    private static func screenPixelSize() -> Int {
        let screens = NSScreen.screens
        let maxPointEdge = screens.map { max($0.frame.width, $0.frame.height) }.max() ?? 1440
        let maxScale = screens.map(\.backingScaleFactor).max() ?? 2
        let pixels = Int((maxPointEdge * maxScale).rounded(.up))
        return min(4096, max(1600, pixels))
    }
}

private extension NSImage {
    /// 近似解码内存占用（RGBA），用于 NSCache 成本计算。
    var approximateByteCost: Int {
        guard let rep = representations.first else { return 0 }
        return max(1, rep.pixelsWide) * max(1, rep.pixelsHigh) * 4
    }
}
