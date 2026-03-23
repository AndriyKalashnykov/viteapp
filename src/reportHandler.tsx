import { Metric } from "web-vitals";

export function reportHandler(metric: Metric) {
  const payload = JSON.stringify(metric);

  navigator.sendBeacon("/analytics", payload);
}
