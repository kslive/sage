import CoreKit
import Foundation
import XCTest
@testable import EditorFeature

@MainActor
final class WebEditorTests: XCTestCase {
    // MARK: - WebEditorController.epoch

    func testSetDocRaisesEpoch() {
        let ctrl = WebEditorController()
        XCTAssertEqual(ctrl.epoch, 0)
        ctrl.setDoc("a")
        XCTAssertEqual(ctrl.epoch, 1)
        ctrl.setDoc("b")
        XCTAssertEqual(ctrl.epoch, 2)
    }

    func testBeginSwitchRaisesEpochWithoutSend() {
        let ctrl = WebEditorController()
        ctrl.beginSwitch()
        XCTAssertEqual(ctrl.epoch, 1)               // поколение поднялось до загрузки нового документа
    }

    // MARK: - Coordinator.docAction (чистое решение по doc-сообщению)

    func testDocActionMatchingEpochApplies() {
        let a = WebEditorView.Coordinator.docAction(incomingEpoch: 5, currentEpoch: 5, text: "hi", flush: false)
        XCTAssertEqual(a, .apply(text: "hi", flush: false))
    }

    func testDocActionStaleEpochIgnored() {
        let a = WebEditorView.Coordinator.docAction(incomingEpoch: 4, currentEpoch: 5, text: "hi", flush: false)
        XCTAssertEqual(a, .ignore)                   // «хвост» прошлого файла отброшен
    }

    func testDocActionNilEpochOrTextIgnored() {
        XCTAssertEqual(WebEditorView.Coordinator.docAction(incomingEpoch: nil, currentEpoch: 5, text: "hi", flush: false), .ignore)
        XCTAssertEqual(WebEditorView.Coordinator.docAction(incomingEpoch: 5, currentEpoch: 5, text: nil, flush: false), .ignore)
    }

    func testDocActionFlushPropagates() {
        let a = WebEditorView.Coordinator.docAction(incomingEpoch: 3, currentEpoch: 3, text: "x", flush: true)
        XCTAssertEqual(a, .apply(text: "x", flush: true))
    }

    // MARK: - Coordinator.decodeImage

    func testDecodeImageValidBase64() {
        let raw = Data([1, 2, 3, 4])
        let body: [String: Any] = ["b64": raw.base64EncodedString(), "ext": "jpg"]
        let out = WebEditorView.Coordinator.decodeImage(body: body)
        XCTAssertEqual(out?.data, raw)
        XCTAssertEqual(out?.ext, "jpg")
    }

    func testDecodeImageDefaultsExtToPng() {
        let body: [String: Any] = ["b64": Data([9]).base64EncodedString()]
        XCTAssertEqual(WebEditorView.Coordinator.decodeImage(body: body)?.ext, "png")
    }

    func testDecodeImageInvalidReturnsNil() {
        XCTAssertNil(WebEditorView.Coordinator.decodeImage(body: ["b64": "не base64!!!"]))
        XCTAssertNil(WebEditorView.Coordinator.decodeImage(body: [:]))
    }
}
