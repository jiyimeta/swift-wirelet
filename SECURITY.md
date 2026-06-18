# Security Policy

## Supported versions

swift-wirelet is pre-1.0 and developed by a single maintainer. Only the
**latest published release** receives security fixes. There are no
long-term support branches; if a vulnerability is confirmed, the fix
ships in a new release and older tags are not back-patched.

| Version | Supported |
|---|---|
| Latest release | ✅ |
| Any earlier release | ❌ |

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.**
Public issues disclose the problem before a fix is available.

Report privately through GitHub's **Private Vulnerability Reporting**:

1. Go to the repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Fill in the advisory form with a description, reproduction steps, and
   the affected version(s) or commit.

This routes the report directly to the maintainer through a private
advisory thread.

> **Maintainer note:** Private Vulnerability Reporting must be enabled
> for this repository under **Settings → Security → Private vulnerability
> reporting**. If the **Report a vulnerability** button is missing from
> the Security tab, the feature has not yet been turned on.

Please include, where you can:

- The affected version, tag, or commit.
- A minimal reproduction (Swift macro / Kotlin emitter input, wire bytes,
  or JNI bridge scenario).
- The impact you observed and any suggested mitigation.

## Response expectations

This is a solo-maintained, pre-1.0 project, so all timelines are
**best-effort** rather than guaranteed:

- Acknowledgment of a report: typically within a few days.
- Initial assessment of severity and validity: as soon as practical
  after acknowledgment.
- Fix and coordinated disclosure: timing depends on severity and
  complexity; the maintainer will keep you updated through the advisory
  thread.

If you do not hear back within a reasonable window, a polite follow-up on
the same private advisory is welcome.
