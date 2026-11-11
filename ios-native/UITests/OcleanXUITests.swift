import XCTest

/* Pruebas de UI de la app nativa. Nacieron para una regresión real:
   el overlay decorativo de GlassCard se comía los toques y ni las filas de
   Historial, ni los controles de Ajustes, ni el 3D respondían al dedo. */
final class OcleanXUITests: XCTestCase {

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    // Tocar una limpieza del historial abre su hoja de detalle.
    func testHistorialAbreDetalle() throws {
        let app = launch(["-seedDemo", "-openTab", "historial"])
        let row = app.buttons["session-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no hay filas de historial")
        row.tap()
        XCTAssertTrue(app.buttons["detail-close"].waitForExistence(timeout: 8),
                      "el detalle no abrió al tocar la fila")
    }

    // Los toggles de Ajustes responden.
    func testAjustesToggleResponde() throws {
        let app = launch(["-seedDemo", "-openTab", "ajustes"])
        let t = app.switches["Aviso de zonas"].firstMatch
        XCTAssertTrue(t.waitForExistence(timeout: 15), "no aparece el toggle")
        let before = t.value as? String
        t.tap()
        let exp = expectation(description: "espera al binding")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exp.fulfill() }
        wait(for: [exp], timeout: 3)
        XCTAssertNotEqual(before, t.value as? String, "el toggle no cambió al tocarlo")
    }

    // El 3D responde al arrastre y al pellizco (gestos SwiftUI -> JS).
    func testRenderGiraYPinch() throws {
        let app = launch(["-seedDemo", "-hoySelectBad", "-openTab", "hoy"])
        let state = app.staticTexts["rot-state"].firstMatch
        XCTAssertTrue(state.waitForExistence(timeout: 20), "no aparece el 3D")
        // OJO: XCTest devuelve SNAPSHOTS OBSOLETOS al leer .label de un elemento
        // ya resuelto. Hay que usar expectativas con predicado (reevaluan con
        // snapshot fresco) o releer la consulta entera cada vez.
        func fresh() -> String { app.staticTexts["rot-state"].firstMatch.label }
        // Las clases con zonas malas tienen que haber llegado al JS (eco por fetch/postMessage)
        let badExp = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "bad"),
            object: app.staticTexts["rot-state"].firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [badExp], timeout: 30), .completed,
                       "las clases reales no llegaron al render. rot-state: \(fresh())")
        let v0 = fresh()
        app.webViews.firstMatch.swipeRight()
        let rotExp = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", v0),
            object: app.staticTexts["rot-state"].firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [rotExp], timeout: 8), .completed,
                       "el arrastre no cambió la rotación. rot-state: \(fresh())")
        let v1 = fresh()
        app.webViews.firstMatch.pinch(withScale: 1.6, velocity: 1)
        let zoomExp = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", v1),
            object: app.staticTexts["rot-state"].firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [zoomExp], timeout: 8), .completed,
                       "el pellizco no cambió el zoom. rot-state: \(fresh())")
    }
}
