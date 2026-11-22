// Mecca Books — connection settings.
// Fill in the two values from Supabase: Project Settings → API (see SETUP.md, step 3).
// The "anon public" key is meant to be public: what each person may see or change
// is enforced by the database itself (row level security), not by keeping this key secret.
window.MB_CONFIG = {
  url: "https://cdfwenlyuoyhcccdtokk.supabase.co",
  anonKey: "sb_publishable_rnstzosaYV-XaIcy69GSYg_PA3cdEKu",
  // logins are usernames; behind the scenes they become  username@staff.secmec.co.za  (no email is ever sent)
  emailDomain: "staff.secmec.co.za"
};
