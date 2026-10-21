// Apple's on-device nudity check (Sensitive Content Analysis, iOS 17+).
// Images never leave the phone. Apple only runs the check when the person has
// turned on Settings › Privacy & Security › Sensitive Content Warning (or
// Communication Safety); otherwise `policy` is "disabled" and the app falls back
// to blurring every incoming chat photo until it is tapped.
import ExpoModulesCore
#if canImport(SensitiveContentAnalysis)
import SensitiveContentAnalysis
#endif

public class QadamSensitiveModule: Module {
  public func definition() -> ModuleDefinition {
    Name("QadamSensitive")

    /// "unavailable" (iOS < 17), "disabled", "simple" or "descriptive".
    AsyncFunction("policy") { () -> String in
      #if canImport(SensitiveContentAnalysis)
      if #available(iOS 17.0, *) {
        switch SCSensitivityAnalyzer().analysisPolicy {
        case .disabled: return "disabled"
        case .simpleInterventions: return "simple"
        case .descriptiveInterventions: return "descriptive"
        @unknown default: return "disabled"
        }
      }
      #endif
      return "unavailable"
    }

    /// true when the image at a local file URI is likely to contain nudity.
    AsyncFunction("analyze") { (uri: String) async throws -> Bool in
      #if canImport(SensitiveContentAnalysis)
      if #available(iOS 17.0, *) {
        guard let url = URL(string: uri), url.isFileURL else {
          throw Exception(name: "BadUri", description: "Expected a local file URI")
        }
        let result = try await SCSensitivityAnalyzer().analyzeImage(at: url)
        return result.isSensitive
      }
      #endif
      throw Exception(name: "Unavailable", description: "Sensitive Content Analysis needs iOS 17")
    }
  }
}
