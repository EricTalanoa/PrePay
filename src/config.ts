// The Supabase URL and publishable key are public by design: they identify the
// project, and row-level security decides what a signed-in user may touch.
// Override either at build time with VITE_SUPABASE_URL / VITE_SUPABASE_KEY.
export const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL || 'https://akdcwtpfxxhtasqtxqdf.supabase.co';
export const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_KEY || 'sb_publishable_C7dJXL4K-MRJb_DIeK373w_s7Fn70pa';
