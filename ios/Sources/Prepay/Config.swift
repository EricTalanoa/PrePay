import Foundation

// The Supabase URL and publishable key are public by design; row-level
// security decides what a signed-in user may touch. Same project as the web app.
enum Config {
    static let supabaseURL = URL(string: "https://akdcwtpfxxhtasqtxqdf.supabase.co")!
    static let supabaseKey = "sb_publishable_C7dJXL4K-MRJb_DIeK373w_s7Fn70pa"
    /// Where the sign-in sheet hands back to the app. Must be listed under
    /// Authentication → URL Configuration → Redirect URLs in Supabase.
    static let authRedirect = URL(string: "prepay://auth-callback")!
}
