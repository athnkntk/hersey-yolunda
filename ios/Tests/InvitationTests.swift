import XCTest
import CoreImage
@testable import HerseyYolunda

final class InvitationTests: XCTestCase {
    func testLinkRoundTripAndCodeNormalization() throws {
        let token = String(repeating: "a", count: 43)
        let link = try XCTUnwrap(InvitationInput.link(token: token))
        XCTAssertEqual(link.scheme, "herseyyolunda")
        XCTAssertEqual(InvitationInput.credentials(link.absoluteString), ["token": token])
        let https = try XCTUnwrap(InvitationInput.link(token: token, domain: "ornek.com"))
        XCTAssertEqual(https.absoluteString, "https://ornek.com/invite?token=\(token)")
        XCTAssertEqual(InvitationInput.credentials(https.absoluteString), ["token": token])
        XCTAssertEqual(InvitationInput.credentials(" https://ornek.com/invite/?token=\(token) "), ["token": token])
        XCTAssertEqual(InvitationInput.credentials(" abcd-efgh-jkmn "), ["code": "ABCDEFGHJKMN"])
        XCTAssertNil(InvitationInput.credentials(UUID().uuidString))
        XCTAssertNil(InvitationInput.credentials("Ayşe"))
        XCTAssertNil(InvitationInput.credentials("https://example.test/other?token=\(token)"))
        XCTAssertNil(InvitationInput.credentials("https://example.test/invite?token=\(token)&token=\(token)"))
        XCTAssertNil(InvitationInput.credentials("http://example.test/invite?token=\(token)"))
        XCTAssertNil(InvitationInput.credentials("herseyyolunda://checkin?token=\(token)"))
    }
    func testQRCodeContainsOnlyTheInvitationLink() throws {
        let link = try XCTUnwrap(InvitationInput.link(token: String(repeating: "b", count: 43)))
        let image = try XCTUnwrap(InvitationQR.image(link.absoluteString)?.cgImage)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let feature = try XCTUnwrap(detector.features(in: CIImage(cgImage: image)).first as? CIQRCodeFeature)
        XCTAssertEqual(feature.messageString, link.absoluteString)
    }
}
