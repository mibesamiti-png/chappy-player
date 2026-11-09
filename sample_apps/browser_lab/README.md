# Browser Lab — Network R7 private Debug manual QA

Browser Lab is a *static* offline manual QA checklist with exactly 12 cases.
It has no `Chappy.network`, WebView navigation, status inspection, native device, PC link or storage bridge.
Only the Chappy Player host BrowserPage opens the public HTTPS WebView, and only the host NetworkDiagnosticPage runs the user-approved one-shot example.com DNS/HTTPS diagnosis.
JavaScript is off by default in the host browser; it never injects a privileged ChappyHost bridge.

Create an unpublished Debug preview:

~~~sh
python3 tools/pack_html_chappy.py --source sample_apps/browser_lab --id local.chappy.browser_lab --name "Browser Lab" --version 0.1.0 --output build/browser-lab-r7.chappy
~~~

The packer generates `permissions: []` automatically. DO NOT add a manifest.json source file, publish the app to Chappy Apps, or include it in signed Stable APK release.

Security and privacy qualifications:
- URL policy only checks top-level/navigation URLs, *not* DNS rebinding, all subresources or native WebView cookie isolation. Browser JS may make network requests after explicit enablement.
- Android WebView may share cookies/cache with other mini-apps; clearing them requires explicit global-data warning. There is no guaranteed per-WebView cookie partition here.
- Do not claim 12/12 QA PASS until a user personally observes them on a physical Android device.
- Existing PC Link two-device 0/15 and R6 media 0/13 checks are unrelated and remain not run.
- Game Server Lab remains a separately permissioned HTTPS/WSS mini-app; no new privileged bridge is wired to it.
