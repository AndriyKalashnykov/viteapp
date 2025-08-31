import { Metric } from "web-vitals";

// event values can only contain integers
function getEventValueFromMetric(metric: Metric) {
  if (metric.name === "CLS") {
    return Math.round(metric.value * 1000);
  }
  return Math.round(metric.value);
}

export function reportHandler(metric: Metric) {
  const payload = JSON.stringify(metric);

  navigator.sendBeacon("/analytics", payload);
}

// function reportHandler(metric: Metric) {
//     ga('send', 'event', {
//         eventCategory: 'Web Vitals',
//         eventAction: metric.name,
//         eventValue: getEventValueFromMetric(metric),
//         eventLabel: metric.id,
//         nonInteraction: true,
//     });
// }
