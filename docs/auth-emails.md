# The sign-in emails

Two emails carry the whole first impression of the portal: the invite, and
the password reset. **Neither lives in this repo.** They are Supabase Auth
templates, and a person has to paste them in:

> Supabase → project **Mosaic Metrics** (`iknjgrltglwupxjtegfh`) →
> Authentication → Emails → **Invite user** / **Reset password**

Nothing in a commit changes them. This file is the source of record for what
they should say, so the wording is reviewable and the next person doesn't have
to guess what was agreed.

## What Loyda asked for, 8 Sep 2026

Walking through her own invite on screen:

- **White, no card, no yellow bar.** "I feel like it's too Claude at the top.
  I think it just could just be white."
- **Say what it is, in bullets.** "A lot of people have had invitations to a
  lot of things… *You've been given a Mosaic Portal account*. What it has is
  combining our metrics, our planning board, and the goals, so that people
  don't think this is new."
- **Cut** "the invite was meant for you if it landed in your inbox by
  mistake." — "I don't know what that means." It is a Supabase default.
- **Cut** "paste this link into your browser" and the long URL. "The URL is
  really long. I don't think that's effective. Might as well just have it go
  to the link."
- **Don't list Comms.** It is internal, and who sees it is a permissions
  question, not a copy question.
- **Say the credentials are the same** if they already have Metrics.
- **Every heading says what the email is.** "Maybe just say reset your
  password… otherwise I may feel like I'm still in the same thing before."

## About the temporary password

Hannita asked for one in the meeting: "we need to make sure it gives you a
temporary password in that email." **These templates do not have one, and it
is worth a deliberate decision rather than a quiet omission.**

Supabase's invite is a one-time link, not a password — `inviteUserByEmail`
never sets one, and the template can only render variables Supabase provides,
so there is nothing to print. Issuing a real temporary password would mean
generating it in the `invite-user` edge function, setting it with the admin
API, and sending the email ourselves through Resend instead of Supabase. That
is a build, not a copy change, and it puts a working password in plain text in
an inbox.

The problem in the meeting was not the absence of a password. It was that the
link did not work: Supabase had moved to PKCE (`?code=`) and the portal only
read the URL hash, so a reset link signed you in and never showed the "set a
password" screen. That is fixed (`5945acf`), and the invite now lands on a
screen headed **Choose your password** (`072dd00`). One link, one screen, no
password in an inbox.

If Hannita still wants the temporary password after that, say so and it can be
built — it is the Resend path above.

---

## Invite user

**Subject**

```
You've been given a Mosaic Portal account
```

**Message body**

```html
<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;
            font-size:15px;line-height:1.6;color:#111;max-width:520px;margin:0;padding:8px 0">

  <p style="margin:0 0 20px">Hi{{ if .Data.first_name }} {{ .Data.first_name }}{{ end }},</p>

  <p style="margin:0 0 16px">
    You've been given a Mosaic Portal account. It isn't a new tool — it's the
    ones you already use, behind one sign-in:
  </p>

  <ul style="margin:0 0 22px;padding-left:20px;color:#111">
    <li style="margin-bottom:6px">Metrics — attendance, decisions and livestream numbers</li>
    <li style="margin-bottom:6px">The planning board — the program year, and what your team owns in it</li>
    <li style="margin-bottom:6px">Goals</li>
    <li style="margin-bottom:6px">Calendars — the church, the staff calendar and facility bookings in one place</li>
  </ul>

  <p style="margin:0 0 24px">
    Choose a password and you're in. If you already sign in to Metrics, it's
    the same account — use the password you already have.
  </p>

  <p style="margin:0 0 28px">
    <a href="{{ .ConfirmationURL }}"
       style="display:inline-block;background:#111;color:#fff;text-decoration:none;
              font-size:15px;font-weight:500;padding:12px 22px;border-radius:8px">
      Set up my account
    </a>
  </p>

  <p style="margin:0;color:#8a8a8a;font-size:13px">
    portal.mosaic.org
  </p>

</div>
```

## Reset password

The one change that matters here is the heading: it has to say what the email
is, so that landing on it doesn't feel like the screen you just left.

**Subject**

```
Reset your Mosaic Portal password
```

**Message body**

```html
<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;
            font-size:15px;line-height:1.6;color:#111;max-width:520px;margin:0;padding:8px 0">

  <p style="margin:0 0 8px;font-size:20px;font-weight:600;letter-spacing:-0.02em">
    Reset your password
  </p>

  <p style="margin:0 0 24px">
    Click below and choose a new one. The link works once, and expires in an
    hour.
  </p>

  <p style="margin:0 0 24px">
    <a href="{{ .ConfirmationURL }}"
       style="display:inline-block;background:#111;color:#fff;text-decoration:none;
              font-size:15px;font-weight:500;padding:12px 22px;border-radius:8px">
      Choose a new password
    </a>
  </p>

  <p style="margin:0 0 20px;color:#555;font-size:14px">
    Didn't ask for this? Nothing has changed — you can ignore this email.
  </p>

  <p style="margin:0;color:#8a8a8a;font-size:13px">
    portal.mosaic.org
  </p>

</div>
```

## Two notes for whoever pastes these

**`{{ .Data.first_name }}` works because the edge function sets it.**
`invite-user` passes `data: { full_name, first_name }` into
`inviteUserByEmail`, so the greeting has a name for anyone invited through the
portal's admin screen. The `{{ if }}` guard means a missing name degrades to a
plain "Hi," rather than "Hi ,".

**The link is `{{ .ConfirmationURL }}` and nothing else.** No second copy of
the URL as text to paste, which is what Loyda struck out.

Worth doing at the same time, though it is a separate change: writing the
invite link as `{{ .SiteURL }}?token_hash={{ .TokenHash }}&type=invite` makes
the type explicit in the URL. Today a PKCE link arrives as a bare `?code=`
that says nothing about whether it was an invite or a reset, so the portal
falls back to wording true of either ("Choose your password"). With `type` in
the link it can always say the right thing. It needs a matching change in the
portal to call `verifyOtp({ token_hash, type })`, so it is a pair of changes,
not one.
