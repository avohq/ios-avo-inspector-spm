//
//  ContentView.swift
//  SpmSandbox
//
//  Created by Alex Verein on 08.12.2021.
//

import SwiftUI
import AvoInspector
import IosAnalyticsDebugger

struct ContentView: View {

    @State private var log: [String] = []
    @State private var inspector: AvoInspector?
    let debugger = AnalyticsDebugger()

    var body: some View {
        NavigationView {
            List {
                // MARK: - Init
                Section("Initialization") {
                    Button("Init (basic)") {
                        inspector = AvoInspector(apiKey: Secrets.apiKey, env: .dev)
                        debugger.showBubble()
                        append("Init basic — OK, lib \(inspector!.libVersion)")
                    }
                    Button("Init (with encryption key)") {
                        inspector = AvoInspector(
                            apiKey: Secrets.apiKey, env: .dev,
                            publicEncryptionKey: Secrets.publicEncryptionKey)
                        debugger.showBubble()
                        append("Init encrypted — OK")
                    }
                    Button("Init (with proxy endpoint)") {
                        inspector = AvoInspector(
                            apiKey: Secrets.apiKey, env: .dev,
                            proxyEndpoint: "https://api.avo.app/inspector/v1/track")
                        append("Init proxy — OK")
                    }
                    Button("Init (prod env)") {
                        inspector = AvoInspector(apiKey: Secrets.apiKey, env: .prod)
                        append("Init prod — OK, logging=\(AvoInspector.isLogging())")
                    }
                    Button("Init (staging env)") {
                        inspector = AvoInspector(apiKey: Secrets.apiKey, env: .staging)
                        append("Init staging — OK")
                    }
                }

                // MARK: - Logging & Config
                Section("Logging & Config") {
                    Button("Toggle logging") {
                        let current = AvoInspector.isLogging()
                        AvoInspector.setLogging(!current)
                        append("Logging: \(!current)")
                    }
                    Button("Set batch size = 5") {
                        AvoInspector.setBatchSize(5)
                        append("Batch size: \(AvoInspector.getBatchSize())")
                    }
                    Button("Set flush interval = 10s") {
                        AvoInspector.setBatchFlushSeconds(10)
                        append("Flush seconds: \(AvoInspector.getBatchFlushSeconds())")
                    }
                }

                // MARK: - Schema Tracking
                Section("Schema Tracking") {
                    Button("trackSchema (simple)") {
                        guard let inspector else { return append("Init first!") }
                        let name = "Account Created"
                        let params: [String: Any] = [
                            "email": "test@avo.app",
                            "age": 28,
                            "verified": true
                        ]
                        let schema = inspector.trackSchema(fromEvent: name, eventParams: params)
                        debugger.debugEvent(name, eventParams: params)
                        append("Tracked — \(formatSchema(schema))")
                    }
                    Button("trackSchema (complex params)") {
                        guard let inspector else { return append("Init first!") }
                        let name = "Purchase Completed"
                        let params: [String: Any] = [
                            "item": "Widget",
                            "price": 9.99,
                            "quantity": 2,
                            "tags": ["sale", "new"],
                            "address": ["city": "Oslo", "zip": 1234],
                            "nothing": NSNull()
                        ]
                        let schema = inspector.trackSchema(fromEvent: name, eventParams: params)
                        debugger.debugEvent(name, eventParams: params)
                        append("Tracked complex — \(formatSchema(schema))")
                    }
                    Button("trackSchema (manual schema)") {
                        guard let inspector else { return append("Init first!") }
                        let name = "Manual Event"
                        let params: [String: Any] = [
                            "name": "test",
                            "count": 1,
                            "active": true
                        ]
                        inspector.trackSchema(name, eventSchema: [
                            "name": AvoString(),
                            "count": AvoInt(),
                            "active": AvoBoolean()
                        ])
                        debugger.debugEvent(name, eventParams: params)
                        append("Tracked manual schema — OK")
                    }
                }

                // MARK: - Schema Extraction
                Section("Schema Extraction") {
                    Button("Extract all types") {
                        guard let inspector else { return append("Init first!") }
                        let schema = inspector.extractSchema([
                            "str": "hello",
                            "int": 42,
                            "float": 3.14,
                            "bool": true,
                            "null": NSNull(),
                            "list": [1, "two", 3.0],
                            "obj": ["nested": "value"]
                        ])
                        append("Extracted — \(formatSchema(schema))")
                    }
                    Button("Extract empty dict") {
                        guard let inspector else { return append("Init first!") }
                        let schema = inspector.extractSchema([:])
                        append("Empty — \(schema.count) keys")
                    }
                }

                // MARK: - Deduplication
                Section("Deduplication") {
                    Button("Track same event twice (fast)") {
                        guard let inspector else { return append("Init first!") }
                        let params: [String: Any] = ["key": "dedup_test"]
                        let r1 = inspector.trackSchema(fromEvent: "Dedup Test", eventParams: params)
                        let r2 = inspector.trackSchema(fromEvent: "Dedup Test", eventParams: params)
                        let firstTracked = !r1.isEmpty
                        let secondDeduped = r2.isEmpty
                        append("1st tracked=\(firstTracked), 2nd deduped=\(secondDeduped)")
                    }
                    Button("Track same event twice (after delay)") {
                        guard let inspector else { return append("Init first!") }
                        let params: [String: Any] = ["key": "delay_test"]
                        let r1 = inspector.trackSchema(fromEvent: "Delay Test", eventParams: params)
                        append("1st tracked=\(!r1.isEmpty), waiting 0.5s...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            let r2 = inspector.trackSchema(fromEvent: "Delay Test", eventParams: params)
                            append("2nd tracked=\(!r2.isEmpty) (should be true after 300ms)")
                        }
                    }
                }

                // MARK: - Lifecycle
                Section("Lifecycle") {
                    Button("enterBackground()") {
                        guard let inspector else { return append("Init first!") }
                        inspector.enterBackground()
                        append("enterBackground — OK")
                    }
                    Button("enterForeground()") {
                        guard let inspector else { return append("Init first!") }
                        inspector.enterForeground()
                        append("enterForeground — OK")
                    }
                }

                // MARK: - Edge Cases
                Section("Edge Cases") {
                    Button("Empty event name") {
                        guard let inspector else { return append("Init first!") }
                        let schema = inspector.trackSchema(fromEvent: "", eventParams: ["a": 1])
                        append("Empty name — \(schema.isEmpty ? "empty" : "ok"), no crash")
                    }
                    Button("Large params (100 keys)") {
                        guard let inspector else { return append("Init first!") }
                        var params = [String: Any]()
                        for i in 0..<100 { params["key_\(i)"] = i }
                        let schema = inspector.trackSchema(fromEvent: "Big Event", eventParams: params)
                        append("100 keys — \(schema.count) types extracted, no crash")
                    }
                    Button("Deeply nested object") {
                        guard let inspector else { return append("Init first!") }
                        let schema = inspector.trackSchema(
                            fromEvent: "Deep Event",
                            eventParams: [
                                "l1": ["l2": ["l3": ["l4": "deep"]]]
                            ])
                        append("Nested — \(formatSchema(schema)), no crash")
                    }
                    Button("Multi-thread stress test") {
                        guard let inspector else { return append("Init first!") }
                        let group = DispatchGroup()
                        for i in 0..<20 {
                            group.enter()
                            DispatchQueue.global().async {
                                _ = inspector.trackSchema(
                                    fromEvent: "Thread \(i)",
                                    eventParams: ["thread": i])
                                group.leave()
                            }
                        }
                        group.notify(queue: .main) {
                            append("20 concurrent calls — no crash")
                        }
                    }
                }

                // MARK: - Validation & Encryption (Form Field Activated)
                Section("Validation & Encryption") {
                    Button("Init with encryption") {
                        inspector = AvoInspector(
                            apiKey: Secrets.apiKey, env: .dev,
                            publicEncryptionKey: Secrets.publicEncryptionKey)
                        debugger.showBubble()
                        append("Init with encryption — OK")
                    }
                    Button("Valid event (all allowed values)") {
                        guard let inspector else { return append("Init with encryption first!") }
                        let name = "Form Field Activated"
                        let params: [String: Any] = [
                            "Form Field": "First Name",
                            "Form Purpose": "Webinar",
                            "Path": "docs/quickstart",
                            "Client": "Web",
                            "Version": "1.0.0",
                            "UTM Source": "google",
                            "UTM Medium": "cpc",
                            "UTM Campaign": "spring",
                            "UTM Term": "analytics",
                            "UTM Content": "banner"
                        ]
                        let schema = inspector.trackSchema(fromEvent: name, eventParams: params)
                        debugger.debugEvent(name, eventParams: params)
                        append("Valid — \(formatSchema(schema))")
                    }
                    Button("Invalid Form Field (bad allowed value)") {
                        guard let inspector else { return append("Init with encryption first!") }
                        let name = "Form Field Activated"
                        let params: [String: Any] = [
                            "Form Field": "Phone Number",
                            "Form Purpose": "Demo",
                            "Path": "docs/quickstart",
                            "Client": "Web",
                            "Version": "1.0.0",
                            "UTM Source": "google",
                            "UTM Medium": "cpc",
                            "UTM Campaign": "spring",
                            "UTM Term": "analytics",
                            "UTM Content": "banner"
                        ]
                        let schema = inspector.trackSchema(fromEvent: name, eventParams: params)
                        debugger.debugEvent(name, eventParams: params)
                        append("Invalid Form Field — \(formatSchema(schema))")
                    }
                    Button("Invalid Form Purpose (bad allowed value)") {
                        guard let inspector else { return append("Init with encryption first!") }
                        let name = "Form Field Activated"
                        let params: [String: Any] = [
                            "Form Field": "Email",
                            "Form Purpose": "Contest",
                            "Path": "docs/quickstart",
                            "Client": "Landing Page",
                            "Version": "2.0.0",
                            "UTM Source": "bing",
                            "UTM Medium": "organic",
                            "UTM Campaign": "fall",
                            "UTM Term": "tracking",
                            "UTM Content": "sidebar"
                        ]
                        let schema = inspector.trackSchema(fromEvent: name, eventParams: params)
                        debugger.debugEvent(name, eventParams: params)
                        append("Invalid Purpose — \(formatSchema(schema))")
                    }
                    Button("Wrong type (int instead of string)") {
                        guard let inspector else { return append("Init with encryption first!") }
                        let name = "Form Field Activated"
                        let params: [String: Any] = [
                            "Form Field": 42,
                            "Form Purpose": "Raffle",
                            "Path": true,
                            "Client": "Cli",
                            "Version": "1.0.0"
                        ]
                        let schema = inspector.trackSchema(fromEvent: name, eventParams: params)
                        debugger.debugEvent(name, eventParams: params)
                        append("Wrong types — \(formatSchema(schema))")
                    }
                    Button("Missing required props") {
                        guard let inspector else { return append("Init with encryption first!") }
                        let name = "Form Field Activated"
                        let params: [String: Any] = [
                            "Form Field": "Last Name"
                        ]
                        let schema = inspector.trackSchema(fromEvent: name, eventParams: params)
                        debugger.debugEvent(name, eventParams: params)
                        append("Missing props — \(formatSchema(schema))")
                    }
                    Button("Extra unexpected prop") {
                        guard let inspector else { return append("Init with encryption first!") }
                        let name = "Form Field Activated"
                        let params: [String: Any] = [
                            "Form Field": "Company",
                            "Form Purpose": "Demo",
                            "Path": "signup",
                            "Client": "Web",
                            "Version": "1.0.0",
                            "Unexpected Extra Prop": "surprise"
                        ]
                        let schema = inspector.trackSchema(fromEvent: name, eventParams: params)
                        debugger.debugEvent(name, eventParams: params)
                        append("Extra prop — \(formatSchema(schema))")
                    }
                    Button("All allowed Form Field values") {
                        guard let inspector else { return append("Init with encryption first!") }
                        let allowedFields = ["First Name", "Last Name", "Email", "Company", "Job Title"]
                        for field in allowedFields {
                            let name = "Form Field Activated"
                            let params: [String: Any] = [
                                "Form Field": field,
                                "Form Purpose": "Webinar",
                                "Path": "docs/test",
                                "Client": "Web",
                                "Version": "1.0.0"
                            ]
                            let schema = inspector.trackSchema(fromEvent: name, eventParams: params)
                            debugger.debugEvent(name, eventParams: params)
                            append("\(field) — \(schema.isEmpty ? "deduped" : "ok")")
                        }
                    }
                }

                // MARK: - Debugger
                Section("Visual Debugger") {
                    Button("Show debugger bubble") {
                        debugger.showBubble()
                        append("Debugger bubble shown")
                    }
                    Button("Send event to debugger") {
                        debugger.debugEvent("Test Event", eventParams: ["key": "value"])
                        append("Debugger event sent")
                    }
                }

                // MARK: - Properties
                Section("Inspector Properties") {
                    Button("Print properties") {
                        guard let inspector else { return append("Init first!") }
                        append("apiKey=\(inspector.apiKey)")
                        append("appVersion=\(inspector.appVersion)")
                        append("libVersion=\(inspector.libVersion)")
                    }
                    Button("Anonymous ID") {
                        let id = AvoAnonymousId.anonymousId()
                        append("anonId=\(id)")
                    }
                }

                // MARK: - Log Output
                Section("Log") {
                    if log.isEmpty {
                        Text("Tap a test above").foregroundColor(.secondary)
                    }
                    ForEach(Array(log.enumerated().reversed()), id: \.offset) { _, entry in
                        Text(entry).font(.caption).lineLimit(3)
                    }
                    if !log.isEmpty {
                        Button("Clear log", role: .destructive) { log.removeAll() }
                    }
                }
            }
            .navigationTitle("AvoInspector QA")
        }
    }

    private func append(_ msg: String) {
        log.append(msg)
    }

    private func formatSchema(_ schema: [String: AvoEventSchemaType]) -> String {
        schema.map { "\($0.key):\($0.value.name())" }
            .sorted()
            .joined(separator: ", ")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
