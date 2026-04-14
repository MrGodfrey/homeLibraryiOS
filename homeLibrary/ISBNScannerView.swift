//
//  ISBNScannerView.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import SwiftUI

#if canImport(UIKit) && canImport(VisionKit)
import UIKit
import VisionKit

enum ISBNScannerAvailability {
    static var isScannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }
}

struct ISBNScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )

        controller.delegate = context.coordinator

        Task { @MainActor in
            do {
                try controller.startScanning()
            } catch {
                onFailure("无法启动扫码，请检查相机权限。")
            }
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let parent: ISBNScannerView
        private var hasScanned = false

        init(parent: ISBNScannerView) {
            self.parent = parent
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasScanned else {
                return
            }

            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    hasScanned = true
                    parent.onCodeScanned(payload)
                    return
                }
            }
        }
    }
}
#else
enum ISBNScannerAvailability {
    static var isScannerAvailable: Bool { false }
}

struct ISBNScannerView: View {
    let onCodeScanned: (String) -> Void
    let onFailure: (String) -> Void

    var body: some View {
        Color.clear
            .onAppear {
                onFailure("当前设备不支持扫码。")
            }
    }
}
#endif
