import Foundation

/// What to say when a turn ends on an API error (Claude Code's `StopFailure`
/// hook). The error codes are Claude Code's; the copy says what happened and,
/// where there is one, the next step.
enum StopFailure {
    struct Copy: Equatable {
        let title: String
        let message: String
    }

    /// `resetsIn` is the 5-hour window's countdown ("1h 12m"), when known.
    static func copy(error: String?, details: String?, resetsIn: String? = nil) -> Copy {
        switch error ?? "unknown" {
        case "rate_limit":
            return Copy(title: NotchNotification.limitsOutTitle,
                        message: resetsIn.map { "Hit the usage limit. Resets in \($0)." } ?? "Hit the usage limit. Try again once it resets.")
        case "overloaded":
            return Copy(title: "Claude is overloaded", message: "The turn stopped. Try again in a moment.")
        case "server_error":
            return Copy(title: "API error", message: "Anthropic's API had a problem. Try again.")
        case "authentication_failed":
            return Copy(title: "Signed out", message: "Run /login in Claude Code, then try again.")
        case "oauth_org_not_allowed":
            return Copy(title: "Login not allowed", message: "Your organisation doesn't allow this login. Run /login with another account.")
        case "account_on_hold":
            return Copy(title: "Account on hold", message: "Your account is on hold. Check your email from Anthropic.")
        case "verification_required":
            return Copy(title: "Verification needed", message: "Finish verifying your account, then try again.")
        case "billing_error":
            return Copy(title: "Billing problem", message: "Check your plan or billing, then try again.")
        case "model_not_found":
            return Copy(title: "Model not found", message: "Pick another model with /model.")
        case "invalid_request":
            return Copy(title: "Request rejected", message: shortDetails(details) ?? "The API rejected the request.")
        case "max_output_tokens":
            return Copy(title: "Reply too long", message: "Hit the output limit. Ask it to continue.")
        case "cloud_credential_error":
            return Copy(title: "Cloud credentials failed", message: "Your Bedrock or Vertex credentials didn't work.")
        default:
            return Copy(title: "Stopped on an error", message: shortDetails(details) ?? "The turn ended on an API error.")
        }
    }

    /// Error details are only worth showing when they read as a sentence, not
    /// as a JSON blob or a stack.
    private static func shortDetails(_ raw: String?) -> String? {
        guard let text = NotchNotification.clean(raw, limit: 140),
              !text.hasPrefix("{"), !text.hasPrefix("[") else { return nil }
        return text
    }
}
