import { tokenHash } from "./google-policy.mjs";

function decodeBase64Json(value) {
  if (globalThis.Buffer) return JSON.parse(globalThis.Buffer.from(value, "base64").toString("utf8"));
  const binary = globalThis.atob(value);
  const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
  return JSON.parse(new TextDecoder().decode(bytes));
}

export function decodePubSubMessage(body, { expectedSubscription, expectedPackageName }) {
  if (!body || body.subscription !== expectedSubscription) throw new Error("wrong_pubsub_subscription");
  const message = body.message;
  if (!message?.messageId || typeof message.data !== "string") throw new Error("invalid_pubsub_message");
  const decoded = decodeBase64Json(message.data);
  if (decoded.packageName !== expectedPackageName) throw new Error("wrong_package");
  const notification = decoded.subscriptionNotification ?? decoded.oneTimeProductNotification ?? decoded.voidedPurchaseNotification;
  if (!notification) throw new Error("missing_rtdn_notification");
  return {
    eventId: message.messageId,
    packageName: decoded.packageName,
    eventTimeMillis: decoded.eventTimeMillis ?? null,
    purchaseToken: notification.purchaseToken,
    purchaseTokenHash: notification.purchaseToken ? tokenHash(notification.purchaseToken) : null,
    subscriptionId: notification.subscriptionId ?? null,
    sku: notification.sku ?? null,
    notificationType: notification.notificationType ?? null,
    raw: decoded,
  };
}

export function rtdnEventRecord(decoded, environment) {
  return {
    provider: "google",
    environment,
    eventId: decoded.eventId,
    providerOriginalId: decoded.purchaseTokenHash,
    eventTimeMillis: decoded.eventTimeMillis,
    raw: decoded.raw,
  };
}
