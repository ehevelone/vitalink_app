const ZIP_CENTROIDS = require("../data/zip-centroids.json");

const EARTH_RADIUS_MILES = 3958.8;
const prefixCache = new Map();

function normalizeZip(value) {
  return String(value || "").match(/^\d{5}/)?.[0] || "";
}

function zipCoordinates(value) {
  const zip = normalizeZip(value);
  const point = ZIP_CENTROIDS[zip];
  return point ? { latitude: point[0], longitude: point[1] } : null;
}

function degreesToRadians(value) {
  return value * Math.PI / 180;
}

function coordinateDistanceMiles(origin, destination) {
  if (!origin || !destination) return null;
  const latitudeDelta = degreesToRadians(
    destination.latitude - origin.latitude,
  );
  const longitudeDelta = degreesToRadians(
    destination.longitude - origin.longitude,
  );
  const originLatitude = degreesToRadians(origin.latitude);
  const destinationLatitude = degreesToRadians(destination.latitude);
  const haversine = Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(originLatitude) * Math.cos(destinationLatitude) *
    Math.sin(longitudeDelta / 2) ** 2;
  return 2 * EARTH_RADIUS_MILES * Math.asin(Math.sqrt(haversine));
}

function zipDistanceMiles(originZip, destinationZip) {
  return coordinateDistanceMiles(
    zipCoordinates(originZip),
    zipCoordinates(destinationZip),
  );
}

function nearbyZipPrefixes(originZip, radiusMiles = 15) {
  const normalizedOrigin = normalizeZip(originZip);
  const cacheKey = `${normalizedOrigin}:${radiusMiles}`;
  if (prefixCache.has(cacheKey)) return prefixCache.get(cacheKey);
  const origin = zipCoordinates(normalizedOrigin);
  if (!origin) return [];

  const prefixes = new Set();
  for (const [zip, point] of Object.entries(ZIP_CENTROIDS)) {
    const distance = coordinateDistanceMiles(origin, {
      latitude: point[0],
      longitude: point[1],
    });
    if (distance <= radiusMiles) prefixes.add(zip.slice(0, 3));
  }
  const result = [...prefixes].sort();
  prefixCache.set(cacheKey, result);
  return result;
}

function candidatesWithinRadius(candidates, originZip, radiusMiles = 15) {
  return (candidates || [])
    .map((candidate) => ({
      ...candidate,
      distanceMiles: zipDistanceMiles(originZip, candidate.postalCode),
    }))
    .filter(
      (candidate) =>
        candidate.distanceMiles != null &&
        candidate.distanceMiles <= radiusMiles,
    )
    .sort((left, right) => left.distanceMiles - right.distanceMiles)
    .map((candidate) => ({
      ...candidate,
      distanceMiles: Math.round(candidate.distanceMiles * 10) / 10,
    }));
}

module.exports = {
  candidatesWithinRadius,
  coordinateDistanceMiles,
  nearbyZipPrefixes,
  normalizeZip,
  zipCoordinates,
  zipDistanceMiles,
};
