import FlutterMacOS
import NaturalLanguage

/// Local sentence similarity for a bounded lexical candidate set. The Dart
/// retriever retains its lexical result whenever embeddings are unavailable.
final class SemanticRetrievalBridge {
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "com.grozziie.jdAutomation.semantic", qos: .userInitiated)
  private var vectors: [String: [Double]] = [:]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.grozziie.jdAutomation/semanticRetrieval",
      binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "score",
            let arguments = call.arguments as? [String: Any],
            let query = arguments["query"] as? String,
            let records = arguments["records"] as? [[String: String]] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.queue.async {
        let scores = self?.scores(query: query, records: records) ?? [:]
        DispatchQueue.main.async { result(scores) }
      }
    }
  }

  private func scores(query: String, records: [[String: String]]) -> [String: Double] {
    guard let embedding = NLEmbedding.sentenceEmbedding(for: .simplifiedChinese),
          let queryVector = embedding.vector(for: query) else {
      return [:]
    }
    var result: [String: Double] = [:]
    for record in records {
      guard let id = record["id"], !id.isEmpty,
            let text = record["text"], !text.isEmpty else { continue }
      let key = "\(id):\(text.hashValue)"
      let vector: [Double]
      if let cached = vectors[key] {
        vector = cached
      } else {
        vector = embedding.vector(for: text) ?? []
        vectors[key] = vector
      }
      guard !vector.isEmpty, vector.count == queryVector.count else { continue }
      var dot = 0.0
      var queryNorm = 0.0
      var recordNorm = 0.0
      for index in vector.indices {
        dot += queryVector[index] * vector[index]
        queryNorm += queryVector[index] * queryVector[index]
        recordNorm += vector[index] * vector[index]
      }
      if queryNorm > 0, recordNorm > 0 {
        result[id] = dot / sqrt(queryNorm * recordNorm)
      }
    }
    return result
  }
}
