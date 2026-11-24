# Selling Notchly Pro

Notchly is free. A Pro license key unlocks the features listed in `Pro.modes` and `Pro.widgets`
([License.swift](Sources/Notchly/Core/License.swift)): the Agents tab (with mascots and agent live activities), the Prompter
tab, and the AI Usage and Pulse widgets. To change what is Pro, edit those two sets.

[Polar](https://polar.sh) sells the key. It is the merchant of record: it runs checkout, collects and pays sales tax and VAT,
sends receipts, handles refunds and subscriptions, and emails the license key. The app has no server and holds no secret:
it calls Polar's public customer-portal license-key endpoints (`activate`, `validate`, `deactivate`).

## Set up (once)

1. **Create a Polar organization** at polar.sh. Do steps 2 to 5 in the **sandbox** first (sandbox.polar.sh, test cards),
   then repeat them in production.
2. **Create the benefit.** Benefits › New › *License Keys*. Recommended: prefix `NOTCHLY`, **Limit activations: 3**
   (the website promises three Macs), no expiry (subscriptions revoke the key when they end).
3. **Create the products** and attach that one benefit to each: for example *Pro Monthly*, *Pro Yearly* (subscriptions)
   and *Pro Lifetime* (one-time). Every product that grants the benefit unlocks Pro.
4. **Create a checkout link** (Products › Checkout Links) that offers the products.
5. **Fill in [License.swift](Sources/Notchly/Core/License.swift) › `enum Pro`:**

   | Constant | Where to find it |
   |---|---|
   | `organizationID` | Settings › General › Organization ID |
   | `benefitID` | Benefits › your License Keys benefit › ID |
   | `checkoutLink` | the checkout link from step 4 |
   | `portalLink` | `https://polar.sh/<your-org-slug>/portal` |
   | `api` | `https://sandbox-api.polar.sh/...` while testing, `https://api.polar.sh/...` for release |

   Also replace `POLAR_CHECKOUT_LINK` in [docs/index.html](docs/index.html) with the checkout link.
6. **Test end to end in the sandbox:** buy with a test card, paste the key in Settings › Notchly Pro, check the Agents tab
   unlocks, refund the order in the dashboard, relaunch Notchly and check Pro locks again. Then switch `api` to production
   and release.

Until `organizationID` and `benefitID` are set, keys cannot be activated and the Pro features stay locked.

## How the app checks a key

| Event | Call | Result |
|---|---|---|
| User pastes a key | `activate` with a device label (`Notchly on Mac15,3`) | Stores the activation ID in `~/Library/Application Support/Notchly/license.json` (mode 0600, not backed up) |
| Launch, then every 12 h | `validate` with the activation ID and `benefit_id` | 200: Pro stays on. 404 (refunded, cancelled, revoked, expired, deactivated): Pro turns off |
| No network, or Polar is down | none succeeds | Pro stays on for 14 days after the last good check |
| User clicks Deactivate | `deactivate` | Frees the activation slot for another Mac |

The check runs in an open-source client, so a person can build Notchly with the check removed. It keeps honest users honest;
the value you sell is the signed build, updates and support.

## Monitor payments, subscriptions and Pro use

Everything is in the Polar dashboard; nothing to host.

| What | Where in Polar |
|---|---|
| Revenue, MRR, orders, churn, conversion | Analytics |
| Each payment, refunds | Sales › Orders |
| Active, cancelled and past-due subscriptions | Sales › Subscriptions |
| Buyers and what they own | Customers |
| Which keys are in use, on how many Macs, last validation | Benefits › License Keys (activations and validation count per key) |
| Real-time alerts | Settings › Webhooks: send `order.paid`, `subscription.canceled`, `refund.created` to a Discord or Slack webhook URL (Polar formats them for both) |

The app sends no analytics (see the Privacy section of the README). The validation count and last-validated time per key in
Polar show which buyers actively use Pro.
