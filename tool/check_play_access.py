#!/usr/bin/env python3
"""Asks Google Play directly whether our service account can read the
subscriptions, and prints the real state of each base plan.

    python3 tool/check_play_access.py [service-account.json]

RevenueCat uses the same API, so when this works RevenueCat works. When it
does not, this says why — which the RevenueCat dashboard often does not.
"""
import base64, glob, json, os, sys, time, urllib.parse, urllib.request, urllib.error

PACKAGE = "com.platepatch.app"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"


def find_key() -> str:
    if len(sys.argv) > 1:
        return sys.argv[1]
    for pattern in (
        os.path.expanduser("~/.config/platepatch/*.json"),
        "gen-lang-client-*.json",
    ):
        hits = glob.glob(pattern)
        if hits:
            return hits[0]
    sys.exit("No service-account JSON found. Pass one as an argument.")


def access_token(sa: dict) -> str:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding

    def b64(data: bytes) -> bytes:
        return base64.urlsafe_b64encode(data).rstrip(b"=")

    now = int(time.time())
    unsigned = (
        b64(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
        + b"."
        + b64(json.dumps({
            "iss": sa["client_email"], "scope": SCOPE,
            "aud": "https://oauth2.googleapis.com/token",
            "iat": now, "exp": now + 3600,
        }).encode())
    )
    key = serialization.load_pem_private_key(sa["private_key"].encode(), password=None)
    signature = key.sign(unsigned, padding.PKCS1v15(), hashes.SHA256())
    assertion = (unsigned + b"." + b64(signature)).decode()

    request = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=urllib.parse.urlencode({
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion,
        }).encode(),
        headers={"content-type": "application/x-www-form-urlencoded"},
    )
    return json.load(urllib.request.urlopen(request, timeout=20))["access_token"]


def main() -> None:
    path = find_key()
    sa = json.load(open(path))
    print(f"service account : {sa['client_email']}")
    print(f"gcp project     : {sa.get('project_id')}\n")

    token = access_token(sa)
    url = (f"https://androidpublisher.googleapis.com/androidpublisher/v3/"
           f"applications/{PACKAGE}/subscriptions")
    try:
        body = json.load(urllib.request.urlopen(
            urllib.request.Request(url, headers={"authorization": f"Bearer {token}"}),
            timeout=25))
    except urllib.error.HTTPError as e:
        detail = json.loads(e.read().decode()).get("error", {})
        print(f"✗ Play refused: {e.code} {detail.get('status')}")
        print(f"  {detail.get('message', '')[:300]}")
        if e.code == 403 and "has not been used" in detail.get("message", ""):
            print("\n  Enable the Google Play Android Developer API in that project.")
        elif e.code == 401:
            print("\n  Invite this service account in Play Console → Users and permissions.")
        sys.exit(1)

    subs = body.get("subscriptions", [])
    print(f"✓ Play answered. Subscriptions visible: {len(subs)}\n")
    if not subs:
        print("  None. They exist in RevenueCat, so check the package name matches.")
    for sub in subs:
        print(f"  {sub.get('productId')}")
        for plan in sub.get("basePlans", []):
            state = plan.get("state", "?")
            mark = "✓" if state == "ACTIVE" else "✗"
            regions = len(plan.get("regionalConfigs", []))
            print(f"    {mark} base plan {plan.get('basePlanId')} — {state}, priced in {regions} regions")
            for offer in plan.get("offers", []) or []:
                print(f"        offer {offer.get('offerId')} — {offer.get('state')}")
        if not sub.get("basePlans"):
            print("    ✗ no base plans — RevenueCat will see no price")


if __name__ == "__main__":
    main()
