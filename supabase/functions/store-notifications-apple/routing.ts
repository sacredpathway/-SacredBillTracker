export function deriveStatus(notificationType: string, subtype: string | null) {
  switch (notificationType) {
    case "SUBSCRIBED":
    case "DID_RENEW":
    case "OFFER_REDEEMED":
    case "DID_CHANGE_RENEWAL_PREF":
    case "DID_CHANGE_RENEWAL_STATUS":
    case "RENEWAL_EXTENDED":
      return "active";
    case "DID_FAIL_TO_RENEW":
      return subtype === "GRACE_PERIOD" ? "in_grace_period" : "on_hold";
    case "GRACE_PERIOD_EXPIRED":
    case "EXPIRED":
      return "expired";
    case "REFUND":
    case "REVOKE":
      return "revoked";
    default:
      return null;
  }
}

export function duplicateDecision(status: string) {
  return status === "processed" || status === "ignored" || status === "permanent_rejection"
    ? "RETURN_SUCCESS"
    : "RETRY_PROCESSING";
}
