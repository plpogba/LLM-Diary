import Foundation
import AppKit
import UniformTypeIdentifiers

class ImageFileManager {
    static let shared = ImageFileManager()
    
    private let fileManager = FileManager.default
    
    private var imagesDirectoryURL: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagesURL = documentsURL.appendingPathComponent("diary_images", isDirectory: true)
        if !fileManager.fileExists(atPath: imagesURL.path) {
            try? fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true, attributes: nil)
        }
        return imagesURL
    }
    
    private init() {
        _ = imagesDirectoryURL
    }
    
    /// 이미지를 파일로 저장하고 생성된 파일명(UUID.jpg)을 반환합니다.
    func saveImage(data: Data) -> String? {
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = imagesDirectoryURL.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL, options: .atomic)
            return filename
        } catch {
            print("Failed to save image data: \(error)")
            return nil
        }
    }
    
    /// NSImage를 압축 JPEG로 저장하고 파일명을 반환합니다.
    func saveImage(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            return nil
        }
        return saveImage(data: jpegData)
    }
    
    /// 파일명으로 로컬 디렉토리에서 NSImage를 불러옵니다.
    func loadImage(filename: String) -> NSImage? {
        let fileURL = imagesDirectoryURL.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return NSImage(contentsOf: fileURL)
    }
    
    /// 파일명에 해당하는 로컬 URL을 반환합니다.
    func imageURL(filename: String) -> URL {
        return imagesDirectoryURL.appendingPathComponent(filename)
    }
    
    /// 단일 이미지 파일 삭제
    func deleteImage(filename: String) {
        let fileURL = imagesDirectoryURL.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
    }
    
    /// 여러 이미지 파일 일괄 삭제
    func deleteImages(filenames: [String]) {
        for filename in filenames {
            deleteImage(filename: filename)
        }
    }
    
    /// macOS 파일 열기 창(NSOpenPanel)을 띄워 사용자가 사진을 선택할 수 있도록 합니다.
    func pickImagesFromPanel(allowsMultipleSelection: Bool = true, completion: @escaping ([NSImage]) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.prompt = "선택"
        openPanel.message = "일기에 첨부할 사진을 선택하세요"
        openPanel.allowsMultipleSelection = allowsMultipleSelection
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [.image, .jpeg, .png, .heic, .webP, .gif]
        
        openPanel.begin { response in
            if response == .OK {
                var loadedImages: [NSImage] = []
                for url in openPanel.urls {
                    if let img = NSImage(contentsOf: url) {
                        loadedImages.append(img)
                    }
                }
                DispatchQueue.main.async {
                    completion(loadedImages)
                }
            }
        }
    }
}
