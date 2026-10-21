# Contributions and future supporter features

## Available in the app

**Audifern → About Audifern**, **Settings → About**, and the menu-bar About action
show the same native content: version/build, the maintainer's public GitHub
profile, the existing mark, license/source links, and contribution options.
The credit is localized as “Made with ❤️ and 🤖 in 🇧🇷”, “Feito com ❤️ e 🤖 no 🇧🇷”,
and “Hecho con ❤️ y 🤖 en 🇧🇷”.

The Mercado Pago button and its QR use the maintainer's supplied public link:
https://link.mercadopago.com.br/sabinosoftware. No identifiers or query parameters
are appended. Opening it requires an explicit action; rendering About makes no
request to Mercado Pago. The app does not receive card details or a payment
confirmation. A scan of this static QR is not attributable to an installation.

The cryptocurrency selector provides Bitcoin on Bitcoin, ETH on Ethereum
mainnet, USDC as an ERC-20 token on Ethereum mainnet, and SOL on Solana mainnet.
The four entries use three public receiving addresses: ETH and USDC intentionally
share one. The exact destinations live in `SupportInfo.swift`; copy actions and
QR generation use that same value. The codes encode **only the receiving
address**, so the donor must choose the displayed asset and network in their
wallet. They do not encode an amount or construct a token transfer. No bank
account, provider account email, private key or API credential is included.

Core Image generates QR codes locally with a white quiet zone in both app
appearances. Tests decode every code and pin the destinations to the values
supplied by the maintainer. Public addresses are intentional publication data;
they are not authentication secrets. Generated design-concept QR images and
placeholder addresses are never shipped.

## Checkout and merchant privacy

Mercado Pago has discontinued the embedded WebView/login integration. On macOS
the app therefore opens the existing hosted link in the default browser, with
the destination visible and ordinary browser login/payment behavior. See
[the provider's WebView notice](https://www.mercadopago.com.br/developers/pt/news/2023/11/30/WebView-integrations-have-been-deprecated).

The provider says the hosted link displays the business identity. A read-only
check on 2026-10-21 found the supplied link reachable with “Sabino Software” in
its public page; it did not find the maintainer's known personal email in that
HTML. This does not establish what appears after login, on Pix details, card
statements, receipts or disputes. No payment was created to test those stages.
See [Mercado Pago's public-link guide](https://www.mercadopago.com.br/blog/seu-link).

An API integration does not itself guarantee that the provider will hide the
merchant's registered identity. Before advertising anonymity, review the
business name, customer-facing contact settings and an actual receipt using
an independent buyer. PagBank's API also provides a hosted
[Checkout and Payment Link](https://developer.pagbank.com.br/docs/checkout);
there is no verified privacy advantage here that warrants replacing the supplied
Mercado Pago link. Any account-setting changes remain an explicit owner action.

## Future installation-linked contributions: proposed design

This section is a design, not a deployed service. There is no donation tracking,
feature restriction, supporter credential or payment backend in the current app.

1. Offer an explicit “Link this contribution to this installation” choice.
   Generate a random installation signing key and store its private part in
   Keychain. Use a public-key hash as the installation reference. Never derive
   it from the Mac serial, advertising ID, Bluetooth address, hearing-aid serial,
   account email, program name or audiogram. Explain the optional upload and
   provide a reset/recovery path.
2. A backend creates a checkout intent and associates its random opaque reference
   with the installation public key. It creates a fresh Mercado Pago preference
   server-side, with the approved amount/currency and a correlation reference.
   Access tokens, webhook secrets and entitlement-signing keys stay in the host's
   secret store. Nothing secret is compiled into the GPL app or committed.
3. Open the returned hosted checkout URL in the browser. A return URL, screenshot,
   QR scan, local flag or a client-supplied payment ID never proves payment.
4. Authenticate notifications with the provider's signature validator, including
   its `x-signature`, `x-request-id` and resource-ID inputs. Persist/deduplicate
   events before acknowledging, then query the authoritative payment resource.
   Verify the receiving account, live/test mode, status, currency, amount and
   checkout correlation before updating supporter state. The receipt and payment
   identifiers remain private backend records.
5. Issue a signed, versioned supporter token containing issuer, app audience,
   installation public-key hash, an opaque token ID, capabilities and validity
   times. The official client checks the signature using a public key only.
   Backend operations additionally require a short-lived challenge signed by the
   installation key. Plan for webhook retries, refunds, chargebacks, key rotation,
   recovery and a documented offline grace period.

Provider details: [creating a checkout preference](https://www.mercadopago.com.br/developers/pt/docs/checkout-pro-preferences/create-payment-preference)
and [authenticating Webhooks and retrieving the payment](https://www.mercadopago.com.br/developers/pt/docs/checkout-pro-preferences/additional-content/notifications/webhooks).
The final API schema and sandbox behavior need validation against the chosen
Mercado Pago application before implementation; the fixed public donation link
does not implement this association by itself.

## What tamper resistance can protect

Signed supporter tokens can make forged or edited tokens fail validation in the
official build. Server checks can protect server-owned benefits. Apple code
signing/notarization helps users identify official downloads. Keep entitlement
issuance auditable, rate-limit recovery, redact logs and test replay/refund cases.

A user controls a local open-source binary and can modify a client-side check.
There is no tamper-proof local paywall to promise. Obfuscation or an embedded
secret does not change that boundary. The GPL app's modification rights remain
intact; see the project's [license](../LICENSE). A supporter badge, optional
cosmetic extras or services whose authorization is checked by the server are
more honest boundaries than a claim that the local app cannot be modified.

Before deploying this optional service, choose the host/domain, account recovery
rules, capabilities, retention policy and provider sandbox credentials. Review
the consent flow and receipts. Deployment and merchant-account changes are not
part of adding the current About screen.
