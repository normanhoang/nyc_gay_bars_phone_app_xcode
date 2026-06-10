import { NYC_REGION, getBarById } from "../bars";
import {
  distanceMiles,
  fullyVisibleNeighborhoods,
  nearestBar,
} from "../geo";

describe("distanceMiles", () => {
  it("roughly matches a known distance", () => {
    // Stonewall Inn → Eagle NYC is about 1.2 miles as the crow flies.
    const eagle = getBarById("eagle-nyc")!;
    const stonewall = getBarById("the-stonewall-inn")!;
    const mi = distanceMiles(stonewall.latitude, stonewall.longitude, eagle);
    expect(mi).toBeGreaterThan(1.0);
    expect(mi).toBeLessThan(1.5);
  });

  it("is ~0 at the bar itself", () => {
    const eagle = getBarById("eagle-nyc")!;
    expect(distanceMiles(eagle.latitude, eagle.longitude, eagle)).toBeCloseTo(
      0,
      5,
    );
  });
});

describe("nearestBar", () => {
  it("returns the bar at its own coordinates", () => {
    const stonewall = getBarById("the-stonewall-inn")!;
    expect(nearestBar(stonewall.latitude, stonewall.longitude).id).toBe(
      "the-stonewall-inn",
    );
  });
});

describe("fullyVisibleNeighborhoods", () => {
  it("sees all 11 neighborhoods in a generous city-wide region", () => {
    const wide = { ...NYC_REGION, latitudeDelta: 1, longitudeDelta: 1 };
    expect(fullyVisibleNeighborhoods(wide)).toBe(11);
  });

  it("sees at most one neighborhood when tightly zoomed in", () => {
    const stonewall = getBarById("the-stonewall-inn")!;
    const tight = {
      latitude: stonewall.latitude,
      longitude: stonewall.longitude,
      latitudeDelta: 0.002,
      longitudeDelta: 0.002,
    };
    expect(fullyVisibleNeighborhoods(tight)).toBeLessThanOrEqual(1);
  });

  it("sees none over the middle of the Atlantic", () => {
    expect(
      fullyVisibleNeighborhoods({
        latitude: 30,
        longitude: -50,
        latitudeDelta: 0.2,
        longitudeDelta: 0.2,
      }),
    ).toBe(0);
  });
});
