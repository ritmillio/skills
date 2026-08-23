# Tracing a scary account to its real source

The user almost never reports the problem. They report **where they saw
something** — a name in a Google account-picker, a login-alert email, an app
asking to sign in as a stranger. The job is to trace that back to a cause before
declaring anything.

## The account-picker is not the account list

Google's "Choose an account" / "Add another account" screen is rendered by
`accounts.google.com` from **Google's own server-side cookies**, not from
anything Chrome synced or stored on the Mac. A name appearing there means that
name touched *the browser's Google session* at some point — often just because
the user, or someone, typed it into a sign-in box. It does **not** mean the
account is signed in, synced, or that its credentials live on the machine.

So `trace.sh` checking the Mac and finding **nothing** is the expected result
even when the picker showed the name. Absence on disk is the reassuring answer,
not a dead end.

## Reading the browser timeline (`trace.sh` §7)

Chromium history stores a `transition` type per visit. The low byte tells you
who drove:

- `1` = the user **typed** the URL (or picked an autocomplete).
- `0` = a **link** was clicked.
- `7` = a **form** was submitted.
- `8` = **reload**.

A flow driven by `1`s and `0`s is the person at the keyboard. That alone rules
out most "someone remotely did this" fears.

## The canonical benign sequence

```
gmail.com                                   (typed)
mail.google.com/.../#inbox                  opened own inbox
.../#inbox/FMfcg...                          opened an email
accounts.google.com/AddSession              "add another account" started
.../v3/signin/identifier                     entered an address
.../signin/challenge/recaptcha
.../signin/challenge/pwd                      password step
.../v3/signin/rejected                        DENIED
```

`AddSession` → `identifier` → `pwd` → **`rejected`** means: a sign-in for some
account was **attempted and denied**. No session was created, no access granted.
If the surrounding history also shows the same name being searched on Google,
LinkedIn, Facebook, YouTube minutes earlier, the whole thing is the user
**researching a person** and idly trying an inbox — not an intrusion.

## What would actually be worrying

- A sign-in flow that ends in **success** (`/signin/oauth/consent` accepted, a
  redirect back to the app with a `code=`) for an account the user doesn't own.
- The account **present in `account_info`** of a browser Preferences file (i.e.
  actually signed in), not just seen in a picker.
- The credential **found in Keychain** for that account.
- History entries at a time the user says they were **not at the machine**,
  driven by `0`/`7` transitions with no preceding `1` (typed) — i.e. someone
  else's session.

## How to report it

State the resolved cause in one line: *"The name came from a rejected AddSession
attempt at 12:53 while you were researching that person — it was denied, no
session exists, and the address is nowhere on the Mac."* Give the user the
timeline as evidence. If they still want cloud-side certainty, point them to the
provider's own security checkup (recent sessions / devices), which this
machine-level skill can't see.
