import WebKit
import XCTest
@testable import VaultCard

@MainActor
final class WebFormAutomationTests: XCTestCase {
    private var webViews: [WKWebView] = []
    private let credentials = CardCredentials(cardNumber: "4111111111111111", expiry: "09/29", cvv: "123", pin: "")

    override func tearDown() {
        webViews.forEach { $0.stopLoading(); $0.removeFromSuperview() }
        webViews.removeAll()
        super.tearDown()
    }

    func testCardFormSubmitsOnceAfterValidationEnablesButton() async throws {
        let web = try await fixture(cardForm(disabled: true))
        let script = GiftCardMallBridge.autofillScript(credentials: credentials)
        try await web.evaluateJavaScript(script)
        try await web.evaluateJavaScript("setTimeout(() => document.querySelector('#submit').disabled = false, 1800); undefined;")
        try await waitFor(web, "document.body.dataset.submissions === '1'")
        try await web.evaluateJavaScript(script)
        try await Task.sleep(for: .milliseconds(350))
        let result = try await web.evaluateJavaScript("[document.body.dataset.submissions, document.querySelector('#credit-card-number').value, document.body.dataset.cancelled || '0']") as? [String]
        XCTAssertEqual(result, ["1", credentials.cardNumber, "0"])
    }

    func testCardFormDoesNotSubmitMissingCVVOrInvalidForm() async throws {
        let web = try await fixture(cardForm(extra: "<input required name='verification' value=''>"))
        try await web.evaluateJavaScript(GiftCardMallBridge.autofillScript(credentials: credentials))
        try await Task.sleep(for: .milliseconds(450))
        let submitted = try await web.evaluateJavaScript("document.body.dataset.submissions || '0'") as? String
        XCTAssertEqual(submitted, "0")
        let incomplete = CardCredentials(cardNumber: credentials.cardNumber, expiry: credentials.expiry, cvv: "", pin: "")
        let missing = try await fixture(cardForm())
        try await missing.evaluateJavaScript(GiftCardMallBridge.autofillScript(credentials: incomplete))
        try await Task.sleep(for: .milliseconds(450))
        let incompleteSubmitted = try await missing.evaluateJavaScript("document.body.dataset.submissions || '0'") as? String
        XCTAssertEqual(incompleteSubmitted, "0")
    }

    func testTransactionDateAppliesToLateFormAndSearchesOnce() async throws {
        let web = try await fixture("<div id='pending'>Loading history</div>")
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let script = GiftCardMallBridge.transactionDateScript(fromDate: date, calendar: calendar)
        try await web.evaluateJavaScript(script)
        let formJSON = String(data: try JSONEncoder().encode(transactionForm), encoding: .utf8)!
        try await web.evaluateJavaScript("document.body.insertAdjacentHTML('beforeend', \(formJSON)); document.querySelector('form').addEventListener('submit', e => { e.preventDefault(); document.body.dataset.submissions = String(+(document.body.dataset.submissions || 0) + 1); }); undefined;")
        try await waitFor(web, "document.body.dataset.submissions === '1'")
        try await web.evaluateJavaScript(script)
        try await Task.sleep(for: .milliseconds(350))
        let result = try await web.evaluateJavaScript("[document.querySelector('#startDate').value, document.querySelector('#End').value, document.body.dataset.submissions]") as? [String]
        XCTAssertEqual(result, ["01/01/2026", "10/24/2026", "1"])
    }

    private var transactionForm: String {
        """
        <app-date-form><form class="date-form">
        <input id="startDate" name="startDate" placeholder="MM/dd/yyyy" value="08/24/2026" required>
        <input id="End" name="endDate" value="10/24/2026" required>
        <button id="btn-search-transaction">Search</button><button type="button" id="btn-check-another-card">Check another card</button>
        </form></app-date-form>
        """
    }

    private func cardForm(disabled: Bool = false, extra: String = "") -> String {
        """
        <form onsubmit="event.preventDefault(); document.body.dataset.submissions = String(+(document.body.dataset.submissions || 0) + 1)">
        <input id="credit-card-number" name="cardNumber" required>
        <input id="expiration_month" name="expirationMonth" required>
        <input id="expiration_year" name="expirationYear" required>
        <input id="credit-card-code" name="cvv" required>
        \(extra)
        <button type="button" onclick="document.body.dataset.cancelled = '1'">Cancel</button>
        <button id="submit" \(disabled ? "disabled" : "")>Submit</button>
        </form>
        """
    }

    private func fixture(_ body: String) async throws -> WKWebView {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        webViews.append(web)
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow })
        window.addSubview(web)
        let loaded = expectation(description: "Local issuer fixture loaded")
        let delegate = FixtureNavigationDelegate(loaded: loaded)
        web.navigationDelegate = delegate
        web.loadHTMLString("<!doctype html><html><body>\(body)</body></html>", baseURL: URL(string: "https://www.mycardwallet.com/chs/mygift/"))
        await fulfillment(of: [loaded], timeout: 5)
        web.navigationDelegate = nil
        return web
    }

    private func waitFor(_ web: WKWebView, _ condition: String) async throws {
        for _ in 0..<100 {
            if try await web.evaluateJavaScript(condition) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Timed out waiting for local form automation")
    }
}

@MainActor
private final class FixtureNavigationDelegate: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation
    init(loaded: XCTestExpectation) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
}
